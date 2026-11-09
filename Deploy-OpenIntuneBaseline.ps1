#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Authentication

<#
.SYNOPSIS
    Deploys the Windows and Windows 365 OpenIntuneBaseline policies to an Intune tenant,
    with update ring groups per policy category and device filters.

.DESCRIPTION
    Works in dependency order, driven by Deployment\DeploymentConfig.json:

      1. Filters      - assignment filters for Cloud PCs and virtual machines
      2. Groups       - "<Category> - Update Ring - <Ring>" security groups, four per category
      3. Policies     - imported from the IntuneManagement exports in the baseline folders
      4. Assignments  - each policy is assigned to its category's ring groups, with a filter
                        where the configuration asks for one

    Rollout is gradual: only the rings named with -Ring are assigned. Start with the Test
    ring, then run the script again with more rings as each one proves stable. Assignments
    are added to whatever a policy already has; nothing is ever removed.

    Groups, filters and policies that already exist (matched by display name) are reused,
    never changed. Apart from adding assignments, the script only creates objects, so it is
    safe to run again.

    The baseline's own three-ring sets (Windows Update, Defender Antivirus updates, driver
    updates) are handled by ringSpecificPolicies: the Production policies go to every ring
    group, and the Pilot and UAT policies are created but left unassigned.

.PARAMETER Ring
    The update rings to assign in this run. Defaults to Test. Run again with, for example,
    -Ring Test,1 to widen the rollout.

.PARAMETER Platform
    Which baselines to deploy: Windows, Windows365, or both (the default).

.PARAMETER PolicyName
    Deploys only the policies matching these wildcard patterns. Policies skipped by default
    (see skipByDefault in the configuration) are included when they match.

.PARAMETER Category
    Deploys only the policies in these categories, for example 'Microsoft Office'.

.PARAMETER SkipAssignments
    Creates filters, groups and policies, but assigns nothing.

.PARAMETER Environment
    CloudNative (the default) deploys the baseline as published. Hybrid is for hybrid-joined
    or on-premises Active Directory environments: it removes the settings listed under
    hybrid.removeSettings in the configuration before creating each policy, and adds
    " - Hybrid" to the names of the policies it changed. Policies left with no settings
    are not deployed. The baseline files on disk are never changed.

.PARAMETER ExportMapping
    Writes a Markdown document to this path showing every group that would be created and
    which policies are assigned to which ring groups and filters, then stops. Does not
    connect to Graph.

.PARAMETER TenantId
    The tenant to connect to. Recommended, to avoid deploying to the wrong tenant.

.PARAMETER ConfigPath
    The deployment configuration file.

.PARAMETER BaselinePath
    The root of the OpenIntuneBaseline repository.

.PARAMETER Force
    Skips the confirmation prompt showing the target tenant.

.EXAMPLE
    .\Deploy-OpenIntuneBaseline.ps1 -TenantId contoso.onmicrosoft.com -WhatIf

    Connects with read-only permissions and shows what would be created and assigned.

.EXAMPLE
    .\Deploy-OpenIntuneBaseline.ps1 -TenantId contoso.onmicrosoft.com

    Creates everything and assigns every policy to its category's Test ring.

.EXAMPLE
    .\Deploy-OpenIntuneBaseline.ps1 -TenantId contoso.onmicrosoft.com -Ring Test,1 -Category 'Microsoft Office'

    Widens the Microsoft Office policies to ring 1.

.EXAMPLE
    .\Deploy-OpenIntuneBaseline.ps1 -TenantId contoso.onmicrosoft.com -Environment Hybrid

    Deploys to the Test ring with the settings that break on-premises AD removed.

.EXAMPLE
    .\Deploy-OpenIntuneBaseline.ps1 -ExportMapping .\Deployment\MAPPING.md

    Regenerates the group and assignment mapping document without connecting to Graph.

.EXAMPLE
    .\Deploy-OpenIntuneBaseline.ps1 -PolicyName '*ASR Rules (L2)*' -Ring Test

    Deploys the ASR L2 policy, which is skipped by default. Remove the audit mode
    policy's assignment for the same ring first, because the two conflict.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateNotNullOrEmpty()]
    [string[]]$Ring = @('Test'),

    [ValidateSet('Windows', 'Windows365')]
    [string[]]$Platform = @('Windows', 'Windows365'),

    [ValidateNotNullOrEmpty()]
    [string[]]$PolicyName,

    [ValidateNotNullOrEmpty()]
    [string[]]$Category,

    [switch]$SkipAssignments,

    [ValidateSet('CloudNative', 'Hybrid')]
    [string]$Environment = 'CloudNative',

    [ValidateNotNullOrEmpty()]
    [string]$ExportMapping,

    [string]$TenantId,

    [string]$ConfigPath = (Join-Path $PSScriptRoot 'Deployment\DeploymentConfig.json'),

    [string]$BaselinePath = $PSScriptRoot,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$GraphV1 = 'https://graph.microsoft.com/v1.0'
$GraphBeta = 'https://graph.microsoft.com/beta'
$Intune = "$GraphBeta/deviceManagement"

# How each exported object type is created, listed and assigned.
$PolicyTypes = @{
    configurationPolicies       = @{ NameProperty = 'name'; SupportsFilters = $true }
    deviceCompliancePolicies    = @{ NameProperty = 'displayName'; SupportsFilters = $true }
    deviceConfigurations        = @{ NameProperty = 'displayName'; SupportsFilters = $true }
    # Driver update profiles do not support assignment filters.
    windowsDriverUpdateProfiles = @{ NameProperty = 'displayName'; SupportsFilters = $false }
}

# Properties in the exports that Graph sets itself and rejects or ignores on create.
$ReadOnlyProperties = @(
    'id', 'createdDateTime', 'lastModifiedDateTime', 'version', 'settingCount', 'creationSource',
    'priorityMetaData', 'supportsScopeTags', 'isAssigned', 'assignments', 'newUpdates',
    'inventorySyncStatus', 'deviceReporting'
)

$script:Results = [System.Collections.Generic.List[object]]::new()
$script:CreatedDirectoryObjects = $false

#region Helpers

function Add-Result {
    param([string]$Type, [string]$Name, [string]$Status, [string]$Id, [string]$Detail)
    $script:Results.Add([pscustomobject]@{
            Type = $Type; Name = $Name; Status = $Status; Id = $Id; Detail = $Detail
        })
    $color = switch ($Status) {
        'Failed' { 'Red' }
        'Skipped' { 'Yellow' }
        { $_ -in 'Created', 'Assigned' } { 'Green' }
        default { 'Gray' }
    }
    $line = "  [$Status] $Name"
    if ($Detail) { $line += " - $Detail" }
    Write-Host $line -ForegroundColor $color
}

function Read-JsonFile {
    param([string]$Path)
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-StringList {
    # Returns a property value as an array without null entries. Wrap the call in
    # parentheses before piping it, otherwise the array travels as one single item.
    param($Value)
    , @(@($Value) | Where-Object { $_ })
}

function Test-NameMatch {
    param([string]$Name, [string[]]$Patterns)
    @($Patterns | Where-Object { $Name -like $_ }).Count -gt 0
}

function Get-ErrorText {
    param($ErrorRecord)
    if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
        return $ErrorRecord.ErrorDetails.Message
    }
    $ErrorRecord.Exception.Message
}

function Get-StatusCode {
    param($ErrorRecord)
    $response = $ErrorRecord.Exception.Response
    if ($response -and $response.StatusCode) { return [int]$response.StatusCode }
    if ((Get-ErrorText $ErrorRecord) -match '\b(400|401|403|404|409|429|500|502|503|504)\b') {
        return [int]$Matches[1]
    }
    0
}

function Invoke-Graph {
    # Calls Graph, waiting and retrying when the service is throttling or unavailable.
    param([string]$Method, [string]$Uri, $Body)

    # Writes are gated by ShouldProcess before they get here. Reads must still run under
    # -WhatIf, otherwise the preview would not see what already exists in the tenant.
    $WhatIfPreference = $false
    $ConfirmPreference = 'None'

    $request = @{ Method = $Method; Uri = $Uri; OutputType = 'PSObject' }
    if ($null -ne $Body) {
        $request.Body = $Body | ConvertTo-Json -Depth 50 -Compress
        $request.ContentType = 'application/json'
    }

    $attempt = 0
    while ($true) {
        $attempt++
        try {
            return Invoke-MgGraphRequest @request
        }
        catch {
            $status = Get-StatusCode $_
            if ($attempt -ge 5 -or $status -notin 429, 500, 502, 503, 504) { throw }
            $delay = [Math]::Pow(2, $attempt) * 5
            $retryAfter = $_.Exception.Response.Headers.RetryAfter.Delta
            if ($retryAfter) { $delay = [Math]::Ceiling($retryAfter.TotalSeconds) }
            Write-Verbose "Graph returned $status, retrying in $delay seconds."
            Start-Sleep -Seconds $delay
        }
    }
}

function Get-GraphCollection {
    param([string]$Uri)
    $items = [System.Collections.Generic.List[object]]::new()
    while ($Uri) {
        $page = Invoke-Graph -Method GET -Uri $Uri
        foreach ($item in @($page.value)) { if ($null -ne $item) { $items.Add($item) } }
        $Uri = $page.'@odata.nextLink'
    }
    , $items.ToArray()
}

function Get-EscapedFilter {
    # Builds an URL-encoded OData "field eq value" filter.
    param([string]$Field, [string]$Value)
    [Uri]::EscapeDataString("$Field eq '$($Value -replace "'", "''")'")
}

function Remove-ExportMetadata {
    # Converts an exported object into a form Graph accepts on POST. Removes null values,
    # annotations (x@odata.y, @odata.id), action links (#microsoft.graph.assign) and unset
    # dates (0001-01-01). "@odata.type" stays: Graph needs it on derived types.
    param($Node)

    if ($null -eq $Node) { return $null }
    # PowerShell 7 turns ISO date strings into DateTime when reading JSON.
    if ($Node -is [datetime]) {
        if ($Node.Year -le 1) { return $null }
        return $Node.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
    if ($Node -is [string]) {
        if ($Node.StartsWith('0001-01-01')) { return $null }
        return $Node
    }
    if ($Node -is [ValueType]) { return $Node }

    if ($Node -is [array]) {
        $items = @(foreach ($item in $Node) { Remove-ExportMetadata $item })
        return , $items
    }

    $clean = [ordered]@{}
    foreach ($property in $Node.PSObject.Properties) {
        if ($property.Name -like '#*') { continue }
        if ($property.Name -like '*@odata.*' -and $property.Name -ne '@odata.type') { continue }
        $value = Remove-ExportMetadata $property.Value
        if ($null -eq $value) { continue }
        $clean[$property.Name] = $value
    }
    $clean
}

function Get-PolicyEndpoint {
    param($Json)
    $type = $Json.'@odata.type'
    if ($type -eq '#microsoft.graph.deviceManagementConfigurationPolicy') { return 'configurationPolicies' }
    if ($type -like '*CompliancePolicy') { return 'deviceCompliancePolicies' }
    if ($type -eq '#microsoft.graph.windowsDriverUpdateProfile') { return 'windowsDriverUpdateProfiles' }
    'deviceConfigurations'
}

function ConvertTo-PolicyBody {
    # Builds the POST body for a policy from its IntuneManagement export.
    param($Policy)

    $json = $Policy.Json
    if ($Policy.Endpoint -eq 'windowsDriverUpdateProfiles') {
        $body = [ordered]@{
            '@odata.type'  = $json.'@odata.type'
            displayName    = $json.displayName
            description    = [string]$json.description
            approvalType   = $json.approvalType
            roleScopeTagIds = (Get-StringList $json.roleScopeTagIds)
        }
        if ($null -ne $json.deploymentDeferralInDays) { $body.deploymentDeferralInDays = $json.deploymentDeferralInDays }
        return $body
    }

    $body = Remove-ExportMetadata $json
    foreach ($readOnly in $ReadOnlyProperties) { $body.Remove($readOnly) }

    switch ($Policy.Endpoint) {
        'configurationPolicies' {
            # A policy only needs the template ID; the rest of the reference is read-only.
            $templateId = $json.templateReference.templateId
            if ($templateId) { $body.templateReference = [ordered]@{ templateId = $templateId } }
            else { $body.Remove('templateReference') }
            foreach ($setting in @($body.settings)) { if ($setting) { $setting.Remove('id') } }
        }
        'deviceCompliancePolicies' {
            # Graph requires exactly one scheduled action rule on create.
            $actions = @(foreach ($rule in @($json.scheduledActionsForRule)) {
                    foreach ($action in @($rule.scheduledActionConfigurations)) {
                        if (-not $action) { continue }
                        $clean = Remove-ExportMetadata $action
                        $clean.Remove('id')
                        $clean
                    }
                })
            if (-not $actions) {
                $actions = @([ordered]@{ actionType = 'block'; gracePeriodHours = 0; notificationTemplateId = ''; notificationMessageCCList = @() })
            }
            $body.scheduledActionsForRule = @([ordered]@{
                    ruleName                      = 'PasswordRequired'
                    scheduledActionConfigurations = $actions
                })
        }
    }
    $body
}

function New-AssignmentTarget {
    param([string]$GroupId, [string]$FilterId, [string]$FilterMode)
    $target = [ordered]@{
        '@odata.type' = '#microsoft.graph.groupAssignmentTarget'
        groupId       = $GroupId
    }
    if ($FilterId) {
        $target.deviceAndAppManagementAssignmentFilterId = $FilterId
        $target.deviceAndAppManagementAssignmentFilterType = $FilterMode
    }
    [ordered]@{ target = $target }
}

#endregion

#region Load configuration

if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "The configuration file '$ConfigPath' was not found." }
$config = Read-JsonFile $ConfigPath
$configRings = Get-StringList $config.rings

$problems = [System.Collections.Generic.List[string]]::new()

foreach ($name in $Ring) {
    if ($name -notin $configRings) { $problems.Add("Ring '$name' is not one of the configured rings: $($configRings -join ', ')") }
}
$categoryNames = @($config.categories | ForEach-Object { $_.name })
foreach ($name in (Get-StringList $Category)) {
    if ($name -notin $categoryNames) { $problems.Add("Category '$name' is not one of: $($categoryNames -join ', ')") }
}
$filtersByKey = @{}
foreach ($filter in @($config.filters)) { $filtersByKey[$filter.key] = $filter }
foreach ($rule in @($config.filterAssignments)) {
    if (-not $filtersByKey.ContainsKey($rule.filter)) { $problems.Add("filterAssignments uses unknown filter '$($rule.filter)'") }
    if ($rule.mode -notin 'include', 'exclude') { $problems.Add("filterAssignments mode must be include or exclude, not '$($rule.mode)'") }
}
if ($problems.Count) { throw "The configuration has problems, nothing was changed:`n  $($problems -join "`n  ")" }

# Reads every policy export and works out its category, rings, filter and default selection.
$allPolicies = [System.Collections.Generic.List[object]]::new()
foreach ($platformName in $Platform) {
    $folder = Join-Path $BaselinePath $config.platforms.$platformName
    if (-not (Test-Path -LiteralPath $folder)) { throw "The $platformName baseline folder '$folder' was not found." }

    foreach ($file in Get-ChildItem -LiteralPath $folder -Recurse -Filter *.json | Sort-Object Name) {
        $json = Read-JsonFile $file.FullName
        $endpoint = Get-PolicyEndpoint $json
        $name = $json.($PolicyTypes[$endpoint].NameProperty)
        if (-not $name) { $problems.Add("$($file.Name): has no display name"); continue }
        $originalName = $name

        # Hybrid: strips the settings that break on-premises AD from the in-memory copy.
        # The baseline files on disk are never changed.
        $hybridRemoved = @()
        $hybridReasons = @()
        $hybridEmpty = $false
        if ($Environment -eq 'Hybrid') {
            $rules = @($config.hybrid.removeSettings | Where-Object { $name -like $_.policy })
            if ($rules -and $endpoint -ne 'configurationPolicies') {
                $problems.Add("$($name): hybrid removeSettings only work on settings catalog policies")
            }
            elseif ($rules) {
                $removeIds = @($rules | ForEach-Object { $_.settings } | Where-Object { $_ })
                $allSettings = @($json.settings)
                $present = @($allSettings | ForEach-Object { $_.settingInstance.settingDefinitionId })
                foreach ($id in $removeIds) {
                    if ($id -notin $present) { $problems.Add("$($name): hybrid setting '$id' is not in the policy. The baseline may have changed; update removeSettings.") }
                }
                $kept = @($allSettings | Where-Object { $_.settingInstance.settingDefinitionId -notin $removeIds })
                $hybridRemoved = @($present | Where-Object { $_ -in $removeIds })
                $hybridReasons = @($rules | ForEach-Object { $_.reason })
                $hybridEmpty = -not $kept

                $json.settings = $kept
                $name = $originalName + $config.hybrid.nameSuffix
                $json.name = $name
                $json.description = (@([string]$json.description, "Hybrid: removed $($hybridRemoved.Count) setting(s) that break on-premises Active Directory.") | Where-Object { $_ }) -join "`n"
            }
        }

        $categoryMatch = @($config.categories | Where-Object { Test-NameMatch $name (Get-StringList $_.match) } | Select-Object -First 1)
        $ringRule = @($config.ringSpecificPolicies | Where-Object { $name -like $_.match } | Select-Object -First 1)
        $filterRule = @($config.filterAssignments | Where-Object { $name -like $_.match } | Select-Object -First 1)
        $skipRule = @($config.skipByDefault | Where-Object { $name -like $_.match } | Select-Object -First 1)

        $allPolicies.Add([pscustomobject]@{
                Name          = $name
                OriginalName  = $originalName
                HybridRemoved = $hybridRemoved
                HybridReasons = $hybridReasons
                HybridEmpty   = $hybridEmpty
                Platform   = $platformName
                File       = $file.FullName
                Json       = $json
                Endpoint   = $endpoint
                Category   = if ($categoryMatch) { $categoryMatch[0].name } else { $null }
                Rings      = if ($ringRule) { Get-StringList $ringRule[0].rings } else { $configRings }
                Filter     = if ($filterRule) { $filterRule[0] } else { $null }
                SkipReason = if ($skipRule) { $skipRule[0].reason } else { $null }
            })
    }
}

if ($ExportMapping) {
    # Writes the full group and assignment plan as Markdown and stops; nothing is sent to Graph.
    function Get-GroupName([string]$CategoryName, [string]$RingName) {
        $config.groupNameFormat.Replace('{category}', $CategoryName).Replace('{ring}', $RingName)
    }
    function Get-PolicyTypeLabel($Policy) {
        switch ($Policy.Endpoint) {
            'configurationPolicies' {
                if ($Policy.Json.templateReference.templateFamily -like 'endpointSecurity*') { 'Endpoint security' } else { 'Settings catalog' }
            }
            'deviceCompliancePolicies' { 'Compliance' }
            'windowsDriverUpdateProfiles' { 'Driver updates' }
            default {
                if ($Policy.Json.'@odata.type' -eq '#microsoft.graph.windowsUpdateForBusinessConfiguration') { 'Update ring' } else { 'Device configuration' }
            }
        }
    }
    function Get-PolicyScope([string]$Name) {
        if ($Name -match ' - D - ') { 'Device' } elseif ($Name -match ' - U - ') { 'User' } else { 'Device' }
    }
    function Format-Cell([string]$Text) { $Text.Replace('|', '\|') }

    if ($problems.Count) { throw "The configuration has problems:`n  $($problems -join "`n  ")" }

    $lines = [System.Collections.Generic.List[string]]::new()
    $deployed = @($allPolicies | Where-Object { -not $_.SkipReason -and -not $_.HybridEmpty })
    $orderedCategories = @($config.categories | ForEach-Object { $_.name } | Where-Object { $_ -in @($allPolicies | ForEach-Object { $_.Category }) })
    $regenerate = ".\Deploy-OpenIntuneBaseline.ps1 -ExportMapping .\Deployment\$(Split-Path $ExportMapping -Leaf)"
    if ($Environment -ne 'CloudNative') { $regenerate += " -Environment $Environment" }

    $lines.Add("# Update ring group and assignment mapping ($Environment)")
    $lines.Add('')
    $lines.Add("Generated from [``DeploymentConfig.json``](DeploymentConfig.json) and the $($Platform -join ' and ') baseline files by ``Deploy-OpenIntuneBaseline.ps1 -ExportMapping``, for the **$Environment** environment. Regenerate it after changing the configuration or updating the baseline:")
    $lines.Add('')
    $lines.Add('```powershell')
    $lines.Add($regenerate)
    $lines.Add('```')
    $lines.Add('')
    $lines.Add("A default run deploys **$($deployed.Count) policies** into **$($orderedCategories.Count) categories**, creating **$($orderedCategories.Count * $configRings.Count) groups** and **$(@($config.filters).Count) filters**. Policies are only assigned to the rings named with ``-Ring`` in each run, so this is the full plan once every ring is rolled out.")
    $lines.Add('')

    $lines.Add('## Groups')
    $lines.Add('')
    $header = '| Category | Policies | ' + (($configRings | ForEach-Object { "Ring $_ group" }) -join ' | ') + ' |'
    $lines.Add($header)
    $lines.Add('| --- | --- | ' + (($configRings | ForEach-Object { '---' }) -join ' | ') + ' |')
    foreach ($categoryName in $orderedCategories) {
        $count = @($deployed | Where-Object { $_.Category -eq $categoryName }).Count
        $cells = $configRings | ForEach-Object { '`' + (Get-GroupName $categoryName $_) + '`' }
        $lines.Add("| [$categoryName](#$(($categoryName.ToLower() -replace '[^a-z0-9 -]', '') -replace ' ', '-')) | $count | $($cells -join ' | ') |")
    }
    $lines.Add('')

    $lines.Add('## Filters')
    $lines.Add('')
    $lines.Add('| Filter | Rule | Applied to |')
    $lines.Add('| --- | --- | --- |')
    foreach ($filter in @($config.filters)) {
        $uses = @($allPolicies | Where-Object { $_.Filter -and $_.Filter.filter -eq $filter.key } | Sort-Object Name |
                ForEach-Object { "$($_.Filter.mode): $($_.Name)" })
        $lines.Add("| ``$($filter.displayName)`` | ``$(Format-Cell $filter.rule)`` | $(if ($uses) { Format-Cell ($uses -join '<br>') } else { 'Not used' }) |")
    }
    $lines.Add('')

    if ($Environment -eq 'Hybrid') {
        $changed = @($allPolicies | Where-Object { $_.HybridRemoved.Count })
        $lines.Add('## Hybrid changes')
        $lines.Add('')
        $lines.Add("These settings are removed before the policies are created, because they break on-premises Active Directory. Changed policies get ``$($config.hybrid.nameSuffix.Trim(' -'))`` added to their names. The baseline files themselves are not changed. Edit ``hybrid.removeSettings`` in the configuration to change the list.")
        $lines.Add('')
        $lines.Add('| Policy | Removed settings | Why |')
        $lines.Add('| --- | --- | --- |')
        foreach ($policy in $changed) {
            $settingsText = ($policy.HybridRemoved | ForEach-Object { '`' + ($_ -replace '^device_vendor_msft_policy_config_', '') + '`' }) -join '<br>'
            $result = if ($policy.HybridEmpty) { '<br>**Not deployed: no settings left.**' } else { '' }
            $lines.Add("| $(Format-Cell $policy.Name) | $settingsText | $(Format-Cell ($policy.HybridReasons -join ' '))$result |")
        }
        $lines.Add('')
    }

    $lines.Add('## Policies by category')
    $lines.Add('')
    $lines.Add('**Rings** lists the ring groups a policy is assigned to once those rings are rolled out. Policies marked *Not assigned* are created but left unassigned, as set in `ringSpecificPolicies`.')
    $lines.Add('')
    foreach ($categoryName in $orderedCategories) {
        $lines.Add("### $categoryName")
        $lines.Add('')
        $lines.Add("Groups: $(($configRings | ForEach-Object { '`' + (Get-GroupName $categoryName $_) + '`' }) -join ', ')")
        $lines.Add('')
        $lines.Add('| Policy | Type | Scope | Rings | Filter |')
        $lines.Add('| --- | --- | --- | --- | --- |')
        foreach ($policy in @($allPolicies | Where-Object { $_.Category -eq $categoryName } | Sort-Object Name)) {
            $name = Format-Cell $policy.Name
            if ($policy.HybridEmpty) { $name = "~~$name~~ *(not deployed in hybrid: all settings removed)*" }
            elseif ($policy.SkipReason) { $name = "~~$name~~ *(skipped by default)*" }
            $rings = if (@($policy.Rings).Count) { $policy.Rings -join ', ' } else { '*Not assigned*' }
            $filterText = if ($policy.Filter) { "$($policy.Filter.mode) ``$($filtersByKey[$policy.Filter.filter].displayName)``" } else { '' }
            $lines.Add("| $name | $(Get-PolicyTypeLabel $policy) | $(Get-PolicyScope $policy.Name) | $rings | $filterText |")
        }
        $lines.Add('')
    }

    $skipped = @($allPolicies | Where-Object SkipReason)
    if ($skipped) {
        $lines.Add('## Skipped by default')
        $lines.Add('')
        $lines.Add('These are created and assigned only when named with `-PolicyName`.')
        $lines.Add('')
        $lines.Add('| Policy | Reason |')
        $lines.Add('| --- | --- |')
        foreach ($policy in $skipped) { $lines.Add("| $(Format-Cell $policy.Name) | $(Format-Cell $policy.SkipReason) |") }
        $lines.Add('')
    }

    $unmapped = @($allPolicies | Where-Object { -not $_.Category })
    if ($unmapped) {
        $lines.Add('## Not in any category')
        $lines.Add('')
        $lines.Add('The script will refuse to deploy these until a category in the configuration matches them.')
        $lines.Add('')
        foreach ($policy in $unmapped) { $lines.Add("- $(Format-Cell $policy.Name)") }
        $lines.Add('')
    }

    $outPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ExportMapping)
    [System.IO.File]::WriteAllText($outPath, ($lines -join "`n"), [System.Text.UTF8Encoding]::new($false))
    Write-Host "Wrote the mapping for $($allPolicies.Count) policies to $outPath"
    return
}

if ($PSBoundParameters.ContainsKey('PolicyName')) {
    $policies = @($allPolicies | Where-Object { Test-NameMatch $_.Name $PolicyName })
}
else {
    $policies = @($allPolicies | Where-Object { -not $_.SkipReason })
    foreach ($skipped in @($allPolicies | Where-Object SkipReason)) {
        Write-Host "Skipping '$($skipped.Name)': $($skipped.SkipReason) Use -PolicyName to include it." -ForegroundColor Yellow
    }
}
if ($Category) { $policies = @($policies | Where-Object { $_.Category -in $Category }) }
foreach ($emptied in @($policies | Where-Object HybridEmpty)) {
    Write-Host "Not deploying '$($emptied.OriginalName)': every setting in it is removed for hybrid environments." -ForegroundColor Yellow
}
$policies = @($policies | Where-Object { -not $_.HybridEmpty })
if (-not $policies) { throw 'No policies match the selection.' }

foreach ($policy in $policies) {
    if (-not $policy.Category) { $problems.Add("$($policy.Name): matches no category in the configuration") }
    foreach ($name in $policy.Rings) {
        if ($name -notin $configRings) { $problems.Add("$($policy.Name): ring-specific ring '$name' is not a configured ring") }
    }
    if ($policy.Filter -and -not $PolicyTypes[$policy.Endpoint].SupportsFilters) {
        $problems.Add("$($policy.Name): has a filter rule, but $($policy.Endpoint) does not support assignment filters")
    }
}
foreach ($duplicate in @($allPolicies | Group-Object Name | Where-Object Count -gt 1)) {
    $problems.Add("$($duplicate.Name): found in more than one file")
}

# Conflicting pairs, from the configuration and from the baseline manifest.
$conflictPairs = [System.Collections.Generic.List[object]]::new()
foreach ($pair in @($config.conflicts)) { $conflictPairs.Add(@($pair)) }
foreach ($platformName in $Platform) {
    $manifestPath = Join-Path (Split-Path (Join-Path $BaselinePath $config.platforms.$platformName)) 'PolicyManifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { continue }
    $manifest = Read-JsonFile $manifestPath
    $namesById = @{}
    foreach ($entry in @($manifest.policies)) { $namesById[$entry.oibId] = $entry.name }
    foreach ($entry in @($manifest.policies)) {
        foreach ($conflictId in (Get-StringList $entry.conflicts)) {
            if ($namesById.ContainsKey($conflictId)) { $conflictPairs.Add(@($entry.name, $namesById[$conflictId])) }
        }
    }
}
# Conflict pairs use the baseline's own names, without the hybrid suffix.
$selectedNames = @($policies | ForEach-Object { $_.OriginalName })
$reported = @{}
foreach ($pair in $conflictPairs) {
    $first = @($selectedNames | Where-Object { $_ -like $pair[0] })
    $second = @($selectedNames | Where-Object { $_ -like $pair[1] })
    if ($first -and $second) {
        $key = (@($first[0], $second[0]) | Sort-Object) -join '|'
        if ($reported.ContainsKey($key)) { continue }
        $reported[$key] = $true
        $problems.Add("'$($first[0])' conflicts with '$($second[0])'. Deploy only one of them; use -PolicyName to choose.")
    }
}

if ($problems.Count) { throw "The configuration has problems, nothing was changed:`n  $($problems -join "`n  ")" }

$neededCategories = @($policies | ForEach-Object { $_.Category } | Sort-Object -Unique)
$neededFilterKeys = @($policies | Where-Object Filter | ForEach-Object { $_.Filter.filter } | Sort-Object -Unique)
$groupCount = $neededCategories.Count * $configRings.Count

Write-Host "Environment: $Environment"
if ($Environment -eq 'Hybrid') {
    $changed = @($policies | Where-Object { $_.HybridRemoved.Count })
    Write-Host "Removed $(@($changed | ForEach-Object { $_.HybridRemoved }).Count) settings from $($changed.Count) policies for on-premises AD compatibility."
}
Write-Host "Loaded $($policies.Count) policies in $($neededCategories.Count) categories, which need $groupCount groups and $($neededFilterKeys.Count) filters."
if ($SkipAssignments) { Write-Host 'Assignments are skipped (-SkipAssignments).' }
else { Write-Host "Rings to assign in this run: $($Ring -join ', ')" }

#endregion

#region Connect

if ($WhatIfPreference) {
    $scopes = @('Group.Read.All', 'DeviceManagementConfiguration.Read.All')
}
else {
    $scopes = @('Group.ReadWrite.All', 'DeviceManagementConfiguration.ReadWrite.All')
}

$context = Get-MgContext
$isUsable = $context -and (-not $TenantId -or $TenantId -eq $context.TenantId) -and
    ($context.AuthType -eq 'AppOnly' -or -not @($scopes | Where-Object { $_ -notin $context.Scopes }).Count)
if (-not $isUsable) {
    $connection = @{ Scopes = $scopes; NoWelcome = $true }
    if ($TenantId) { $connection.TenantId = $TenantId }
    $null = & {
        $WhatIfPreference = $false
        Connect-MgGraph @connection
    }
    $context = Get-MgContext
}
if (-not $context) { throw 'Could not connect to Microsoft Graph.' }

Write-Host "Target tenant: $($context.TenantId)  Account: $($context.Account)"

if (-not $WhatIfPreference -and -not $Force) {
    $question = "Create up to $($neededFilterKeys.Count) filters, $groupCount groups and $($policies.Count) policies in tenant $($context.TenantId)"
    if (-not $SkipAssignments) { $question += ", and assign them to ring(s) $($Ring -join ', ')" }
    if (-not $PSCmdlet.ShouldContinue("$question?", 'Deploy OpenIntuneBaseline')) {
        Write-Host 'Cancelled, nothing was changed.'
        return
    }
}

#endregion

#region Filters

Write-Host "`nFilters"
$filterMap = @{}
if ($neededFilterKeys) {
    $existingFilters = Get-GraphCollection "$Intune/assignmentFilters"
}
foreach ($key in $neededFilterKeys) {
    $filter = $filtersByKey[$key]
    $name = $filter.displayName
    try {
        $match = @($existingFilters | Where-Object { $_.displayName -eq $name })
        if ($match.Count -gt 1) { throw "$($match.Count) filters in the tenant have this name, so the right one is unclear." }
        if ($match.Count -eq 1) {
            if ($match[0].platform -ne 'windows10AndLater') { throw "A filter with this name exists for platform '$($match[0].platform)', not Windows." }
            $filterMap[$key] = $match[0].id
            $detail = ''
            if (($match[0].rule -replace '\s', '') -ne ($filter.rule -replace '\s', '')) {
                $detail = "Kept the existing rule instead of the configured one: $($match[0].rule)"
            }
            Add-Result 'Filter' $name 'Exists' $match[0].id $detail
            continue
        }

        $body = [ordered]@{
            displayName                    = $name
            description                    = [string]$filter.description
            platform                       = 'windows10AndLater'
            rule                           = $filter.rule
            assignmentFilterManagementType = 'devices'
        }
        Write-Verbose "Filter body: $($body | ConvertTo-Json -Depth 10)"

        if ($PSCmdlet.ShouldProcess($name, 'Create assignment filter')) {
            $created = Invoke-Graph -Method POST -Uri "$Intune/assignmentFilters" -Body $body
            $filterMap[$key] = $created.id
            Add-Result 'Filter' $name 'Created' $created.id
        }
        else {
            $filterMap[$key] = [guid]::Empty.ToString()
            Add-Result 'Filter' $name 'WhatIf'
        }
    }
    catch {
        Add-Result 'Filter' $name 'Failed' '' (Get-ErrorText $_)
    }
}

#endregion

#region Groups

Write-Host "`nGroups"
$groupMap = @{}
foreach ($categoryName in $neededCategories) {
    foreach ($ringName in $configRings) {
        $name = $config.groupNameFormat.Replace('{category}', $categoryName).Replace('{ring}', $ringName)
        $key = "$categoryName|$ringName"
        try {
            $existing = Get-GraphCollection "$GraphV1/groups?`$select=id,displayName,securityEnabled&`$filter=$(Get-EscapedFilter 'displayName' $name)"
            if ($existing.Count -gt 1) { throw "$($existing.Count) groups in the tenant have this name, so the right one is unclear." }
            if ($existing.Count -eq 1) {
                if (-not $existing[0].securityEnabled) { throw 'A group with this name exists but is not security enabled, so it cannot be assigned.' }
                $groupMap[$key] = $existing[0].id
                Add-Result 'Group' $name 'Exists' $existing[0].id
                continue
            }

            $body = [ordered]@{
                displayName     = $name
                description     = "OpenIntuneBaseline update ring $ringName for $categoryName policies. Add users or devices to roll the policies out to them."
                mailEnabled     = $false
                mailNickname    = 'oib-' + [guid]::NewGuid().ToString('N').Substring(0, 10)
                securityEnabled = $true
                groupTypes      = @()
            }
            Write-Verbose "Group body: $($body | ConvertTo-Json -Depth 10)"

            if ($PSCmdlet.ShouldProcess($name, 'Create group')) {
                $created = Invoke-Graph -Method POST -Uri "$GraphV1/groups" -Body $body
                $groupMap[$key] = $created.id
                $script:CreatedDirectoryObjects = $true
                Add-Result 'Group' $name 'Created' $created.id
            }
            else {
                $groupMap[$key] = [guid]::Empty.ToString()
                Add-Result 'Group' $name 'WhatIf'
            }
        }
        catch {
            Add-Result 'Group' $name 'Failed' '' (Get-ErrorText $_)
        }
    }
}

#endregion

#region Policies and assignments

Write-Host "`nPolicies"

$existingByEndpoint = @{}
foreach ($endpoint in @($policies | ForEach-Object { $_.Endpoint } | Sort-Object -Unique)) {
    $nameProperty = $PolicyTypes[$endpoint].NameProperty
    $uri = "$Intune/$endpoint"
    if ($endpoint -ne 'windowsDriverUpdateProfiles') { $uri += "?`$select=id,$nameProperty" }
    # Get-GraphCollection returns its array as one object; the parentheses unroll it.
    $existingByEndpoint[$endpoint] = @((Get-GraphCollection $uri) | ForEach-Object {
            [pscustomobject]@{ Id = $_.id; Name = $_.$nameProperty }
        })
}

foreach ($policy in ($policies | Sort-Object Category, Name)) {
    $name = $policy.Name
    $policyId = $null
    $isNew = $false

    $existing = @($existingByEndpoint[$policy.Endpoint] | Where-Object { $_.Name -eq $name })
    if ($existing.Count -gt 1) {
        Add-Result 'Policy' $name 'Failed' '' "$($existing.Count) policies in the tenant have this name, so the right one is unclear."
        continue
    }
    if ($existing.Count -eq 1) {
        $policyId = $existing[0].Id
        Add-Result 'Policy' $name 'Exists' $policyId 'Settings left unchanged.'
    }
    else {
        try {
            $body = ConvertTo-PolicyBody $policy
            $createDetail = $policy.Category
            if ($policy.HybridRemoved.Count) { $createDetail += "; hybrid: removed $($policy.HybridRemoved.Count) setting(s)" }
            Write-Verbose "Policy body: $($body | ConvertTo-Json -Depth 50)"
            if ($PSCmdlet.ShouldProcess($name, 'Create policy')) {
                $created = Invoke-Graph -Method POST -Uri "$Intune/$($policy.Endpoint)" -Body $body
                $policyId = $created.id
                Add-Result 'Policy' $name 'Created' $policyId $createDetail
            }
            else {
                Add-Result 'Policy' $name 'WhatIf' '' $createDetail
            }
            $isNew = $true
        }
        catch {
            Add-Result 'Policy' $name 'Failed' '' (Get-ErrorText $_)
            continue
        }
    }

    if ($SkipAssignments) { continue }

    if (-not @($policy.Rings).Count) {
        Add-Result 'Assignment' $name 'Unassigned' $policyId 'Left unassigned by ringSpecificPolicies.'
        continue
    }
    $assignRings = @($policy.Rings | Where-Object { $_ -in $Ring })
    if (-not $assignRings) { continue }

    $filterId = $null
    $filterMode = $null
    if ($policy.Filter) {
        $filterId = $filterMap[$policy.Filter.filter]
        $filterMode = $policy.Filter.mode
        if (-not $filterId) {
            Add-Result 'Assignment' $name 'Failed' '' "Filter '$($filtersByKey[$policy.Filter.filter].displayName)' was not created, so the policy was not assigned."
            continue
        }
    }

    try {
        # Assigning replaces all of a policy's assignments, so the current ones are sent too.
        $current = @()
        if ($policyId) {
            $current = Get-GraphCollection "$Intune/$($policy.Endpoint)/$policyId/assignments"
        }
        $currentGroupIds = @($current | ForEach-Object { $_.target.groupId } | Where-Object { $_ })

        $newAssignments = [System.Collections.Generic.List[object]]::new()
        $addedRings = [System.Collections.Generic.List[string]]::new()
        $notes = [System.Collections.Generic.List[string]]::new()
        foreach ($ringName in $assignRings) {
            $groupId = $groupMap["$($policy.Category)|$ringName"]
            if (-not $groupId) { $notes.Add("ring $ringName group was not created"); continue }
            if ($groupId -in $currentGroupIds) { continue }
            $newAssignments.Add((New-AssignmentTarget -GroupId $groupId -FilterId $filterId -FilterMode $filterMode))
            $addedRings.Add($ringName)
        }

        if (-not $newAssignments.Count) {
            $status = if ($notes.Count) { 'Failed' } else { 'Exists' }
            $detail = if ($notes.Count) { $notes -join '; ' } else { "Already assigned to ring(s) $($assignRings -join ', ')." }
            Add-Result 'Assignment' $name $status $policyId $detail
            continue
        }

        $detail = "ring(s) $($addedRings -join ', ')"
        if ($policy.Filter) { $detail += ", $($filterMode) filter '$($filtersByKey[$policy.Filter.filter].displayName)'" }
        if ($notes.Count) { $detail += "; $($notes -join '; ')" }

        if (-not $policyId -or -not $PSCmdlet.ShouldProcess($name, "Assign to $detail")) {
            Add-Result 'Assignment' $name 'WhatIf' '' $detail
            continue
        }

        $assignments = @(foreach ($item in $current) { [ordered]@{ target = (Remove-ExportMetadata $item.target) } }) + $newAssignments.ToArray()
        $body = @{ assignments = $assignments }
        Write-Verbose "Assignment body: $($body | ConvertTo-Json -Depth 10)"

        # New groups can take a moment to become visible to Intune, which shows up as a 400.
        $attempt = 0
        while ($true) {
            $attempt++
            try {
                $null = Invoke-Graph -Method POST -Uri "$Intune/$($policy.Endpoint)/$policyId/assign" -Body $body
                break
            }
            catch {
                if (($script:CreatedDirectoryObjects -or $isNew) -and $attempt -lt 4 -and (Get-StatusCode $_) -in 400, 404) {
                    Write-Verbose "$name returned $(Get-StatusCode $_) on assign, retrying in case of replication delay."
                    Start-Sleep -Seconds (15 * $attempt)
                    continue
                }
                throw
            }
        }
        $status = if ($notes.Count) { 'Failed' } else { 'Assigned' }
        Add-Result 'Assignment' $name $status $policyId $detail
    }
    catch {
        Add-Result 'Assignment' $name 'Failed' $policyId (Get-ErrorText $_)
    }
}

#endregion

#region Summary

Write-Host "`nSummary"
$script:Results | Group-Object Type, Status | Sort-Object Name | ForEach-Object {
    Write-Host ("  {0,-30} {1}" -f $_.Name, $_.Count)
}

if (-not $SkipAssignments -and -not $WhatIfPreference) {
    Write-Host "`nAdd users or devices to the '<Category> - Update Ring - <Ring>' groups to roll the policies out to them."
}
if ($WhatIfPreference) {
    Write-Host "`nNo changes were made (-WhatIf)."
}

$script:Results

if (@($script:Results | Where-Object Status -eq 'Failed').Count) {
    Write-Error 'One or more objects failed. Fix the cause and run the script again; existing objects are reused.' -ErrorAction Continue
    exit 1
}

#endregion
