#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Authentication

<#
.SYNOPSIS
    Deploys the Windows and Windows 365 OpenIntuneBaseline policies to an Intune tenant,
    with update ring groups per policy category and device filters.

.DESCRIPTION
    Works in dependency order, driven by Deployment\DeploymentConfig.json:

      1. Filters      - assignment filters for Cloud PCs and virtual machines
      2. Groups       - "<Category> - Update Ring - <Ring> - <Audience>" security groups, four
                        per category for each audience (Users, Devices) its policies target.
                        User-scoped (- U -) policies go to the Users groups, everything else to
                        the Devices groups. Groups are static by default; -DynamicDeviceRings
                        and -DynamicUserRings make rings 1 to 3 dynamic using the rules in the
                        configuration
      3. Policies     - imported from the IntuneManagement exports in the baseline folders
      4. Assignments  - each policy is assigned to its category's ring groups, with a filter
                        where the configuration asks for one

    Rollout is gradual: only the rings named with -Ring are assigned. Start with the Test
    ring, then run the script again with more rings as each one proves stable. Assignments
    are added to whatever a policy already has; nothing is ever removed.

    Groups, filters and policies that already exist (matched by display name) are reused,
    never changed, unless -UpdateGroupRules is used to switch existing ring groups between
    static and dynamic. Apart from that and adding assignments, the script only creates
    objects, so it is safe to run again.

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

.PARAMETER TestRingOnly
    For small tenants where update rings are overkill. Creates only the Test ring groups for
    each category and audience, and assigns every policy to them. The baseline's Production
    update policies go to the Test groups, and Pilot and UAT stay unassigned as usual.
    Existing ring 1 to 3 groups are not touched.

.PARAMETER DynamicDeviceRings
    Creates the Devices ring groups for rings 1 to 3 as dynamic groups, using the Devices
    audience's dynamicRules in the configuration (Windows MDM devices, split by the first
    character of the device ID). Without it, all groups are static. Needs Entra ID P1.

.PARAMETER DynamicUserRings
    Creates the Users ring groups for rings 1 to 3 as dynamic groups, using the Users
    audience's dynamicRules in the configuration (enabled member users, split by the first
    character of the object ID). Without it, all groups are static. Needs Entra ID P1.

.PARAMETER UpdateGroupRules
    Brings ring groups that already exist in line with this run's choice of static or dynamic:
    converts dynamic groups to static (keeping their current members), converts static groups
    to dynamic, and updates rules that differ. A static group that has members is not
    converted to dynamic, because converting it would remove them. Without this switch,
    existing groups are left as they are and any difference is reported. Running it without
    -DynamicDeviceRings or -DynamicUserRings converts those dynamic groups back to static.

.PARAMETER Environment
    CloudNative (the default) deploys the baseline as published. Hybrid is for hybrid-joined
    or on-premises Active Directory environments: it removes the settings listed under
    hybrid.removeSettings in the configuration before creating each policy, and adds
    " - Hybrid" to the names of the policies it changed. Policies left with no settings
    are not deployed. The baseline files on disk are never changed.

.PARAMETER Overlay
    The overlay to apply on top of the upstream baseline: an organisation's own versions of
    some policies, plus baseline policies to leave out, defined under overlays in the
    configuration. Defaults to defaultOverlay in the configuration (Gnosis). Use None to
    deploy the upstream baseline unchanged. The upstream folders are never modified, so they
    can still be updated from upstream.

.PARAMETER IncludeUpdatePolicies
    Deploys the Windows Update rings and driver profiles that the overlay leaves out
    (excludeUpdatePolicies in the configuration). The Gnosis overlay leaves them out because
    ConnectWise RMM normally manages updates; use this for tenants where it doesn't. The
    upstream baseline (-Overlay None) always includes them.

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
    .\Deploy-OpenIntuneBaseline.ps1 -TenantId contoso.onmicrosoft.com -IncludeUpdatePolicies

    For a tenant where ConnectWise RMM doesn't manage updates: also deploys the Windows
    Update rings and driver profiles.

.EXAMPLE
    .\Deploy-OpenIntuneBaseline.ps1 -TenantId contoso.onmicrosoft.com -TestRingOnly

    For a small tenant: creates only the Test groups and assigns every policy to them.

.EXAMPLE
    .\Deploy-OpenIntuneBaseline.ps1 -TenantId contoso.onmicrosoft.com -DynamicDeviceRings -DynamicUserRings

    Deploys with dynamic ring 1 to 3 groups for both devices and users; Test stays static.

.EXAMPLE
    .\Deploy-OpenIntuneBaseline.ps1 -TenantId contoso.onmicrosoft.com -SkipAssignments -DynamicDeviceRings -UpdateGroupRules

    Converts existing static Devices ring groups to dynamic, without touching assignments.
    Run it without -DynamicDeviceRings to convert them back to static.

.EXAMPLE
    .\Deploy-OpenIntuneBaseline.ps1 -TenantId contoso.onmicrosoft.com -Environment Hybrid

    Deploys to the Test ring with the settings that break on-premises AD removed.

.EXAMPLE
    .\Deploy-OpenIntuneBaseline.ps1 -ExportMapping .\Deployment\MAPPING.md

    Regenerates the group and assignment mapping document without connecting to Graph.

.EXAMPLE
    .\Deploy-OpenIntuneBaseline.ps1 -PolicyName '*BitLocker*' -Ring Test

    Deploys only the BitLocker policies and assigns them to the Test ring.
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

    [switch]$TestRingOnly,

    [switch]$DynamicDeviceRings,

    [switch]$DynamicUserRings,

    [switch]$UpdateGroupRules,

    [ValidateSet('CloudNative', 'Hybrid')]
    [string]$Environment = 'CloudNative',

    [ValidateNotNullOrEmpty()]
    [string]$Overlay,

    [switch]$IncludeUpdatePolicies,

    [ValidateNotNullOrEmpty()]
    [string]$ExportMapping,

    [string]$TenantId,

    [string]$ConfigPath = (Join-Path $PSScriptRoot 'Deployment\DeploymentConfig.json'),

    [string]$BaselinePath = $PSScriptRoot,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# "pwsh -File script.ps1 -Ring Test,1" passes "Test,1" as one string, so split lists here.
# -PolicyName is left alone because policy names can contain commas.
$Ring = @($Ring | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($Category) { $Category = @($Category | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }

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
        { $_ -in 'Created', 'Assigned', 'Updated' } { 'Green' }
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

function Get-OibId {
    # The baseline's own policy ID, from the "OIBID:" tag in the description.
    param($Json)
    if ([string]$Json.description -match 'OIBID:([0-9A-Fa-f-]{36})') { $Matches[1].ToUpperInvariant() } else { '' }
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

function Get-ConfiguredRule {
    # The dynamic membership rule configured for an audience's ring, whether or not it is in use.
    param([string]$AudienceName, [string]$RingName)
    $audience = @($config.audiences | Where-Object { $_.name -eq $AudienceName })[0]
    if (-not $audience -or -not $audience.dynamicRules) { return $null }
    $property = $audience.dynamicRules.PSObject.Properties[$RingName]
    if ($property -and $property.Value) { [string]$property.Value } else { $null }
}

function Get-RingRule {
    # The rule to use for an audience's ring in this run: $null (static) unless the
    # audience's dynamic switch, such as -DynamicDeviceRings, was passed.
    param([string]$AudienceName, [string]$RingName)
    if ($AudienceName -notin $script:DynamicAudiences) { return $null }
    Get-ConfiguredRule $AudienceName $RingName
}

function Get-GroupName {
    param([string]$CategoryName, [string]$RingName, [string]$AudienceName)
    $config.groupNameFormat.Replace('{category}', $CategoryName).Replace('{ring}', $RingName).Replace('{audience}', $AudienceName)
}

function Format-Rule {
    # Normalises a membership rule for comparison; Entra may change spacing and case.
    param([string]$Rule)
    ($Rule -replace '\s', '').ToLowerInvariant()
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
$allConfigRings = Get-StringList $config.rings
# -TestRingOnly narrows every ring list to the first configured ring (Test), so no other
# ring groups are created and every policy is assigned to the Test groups.
$configRings = @(if ($TestRingOnly) { $allConfigRings[0] } else { $allConfigRings })

$problems = [System.Collections.Generic.List[string]]::new()

foreach ($name in $Ring) {
    if ($name -notin $allConfigRings) { $problems.Add("Ring '$name' is not one of the configured rings: $($allConfigRings -join ', ')") }
    elseif ($name -notin $configRings) { $problems.Add("Ring '$name' can't be used with -TestRingOnly, which only has the $($configRings[0]) ring.") }
}
foreach ($rule in @($config.ringSpecificPolicies)) {
    foreach ($name in (Get-StringList $rule.rings)) {
        if ($name -notin $allConfigRings) { $problems.Add("ringSpecificPolicies '$($rule.match)' uses ring '$name', which is not a configured ring") }
    }
}
if ($TestRingOnly -and ($DynamicDeviceRings -or $DynamicUserRings)) {
    Write-Warning "-DynamicDeviceRings and -DynamicUserRings have no effect with -TestRingOnly: the $($configRings[0]) groups are always static."
}
$audienceNames = @($config.audiences | ForEach-Object { $_.name })
if (-not $audienceNames) { $problems.Add('The configuration has no audiences.') }
if ($audienceNames.Count -gt 1 -and $config.groupNameFormat -notlike '*{audience}*') { $problems.Add('groupNameFormat must contain {audience} when there is more than one audience.') }
$dynamicSwitches = @{ DynamicUserRings = [bool]$DynamicUserRings; DynamicDeviceRings = [bool]$DynamicDeviceRings }
$script:DynamicAudiences = @()
foreach ($audience in @($config.audiences)) {
    foreach ($property in @($audience.dynamicRules.PSObject.Properties)) {
        if ($property.Name -notin $allConfigRings) { $problems.Add("Audience '$($audience.name)' has a dynamic rule for ring '$($property.Name)', which is not one of the configured rings: $($allConfigRings -join ', ')") }
        elseif ($property.Value -and $property.Value -match '[“”‘’]') { $problems.Add("The $($audience.name) dynamic rule for ring '$($property.Name)' contains curly quotes; use straight quotes (`").") }
    }
    if ($audience.dynamicSwitch) {
        if (-not $dynamicSwitches.ContainsKey($audience.dynamicSwitch)) { $problems.Add("Audience '$($audience.name)' has dynamicSwitch '$($audience.dynamicSwitch)'; it must be one of: $($dynamicSwitches.Keys -join ', ')") }
        elseif ($dynamicSwitches[$audience.dynamicSwitch]) { $script:DynamicAudiences += $audience.name }
    }
}
foreach ($switchName in @($dynamicSwitches.Keys | Where-Object { $dynamicSwitches[$_] })) {
    $owners = @($config.audiences | Where-Object { $_.dynamicSwitch -eq $switchName })
    if (-not $owners) { $problems.Add("-$switchName was passed, but no audience in the configuration uses it.") }
    foreach ($owner in $owners) {
        if (-not @($owner.dynamicRules.PSObject.Properties | Where-Object Value).Count) { $problems.Add("-$switchName was passed, but audience '$($owner.name)' has no dynamicRules.") }
    }
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

# Overlay: an organisation's own versions of some baseline policies, plus baseline policies
# to leave out. The upstream baseline folders are never changed, so they can still be
# updated from upstream; the overlay is applied on top when the policies are loaded.
$overlayName = if ($PSBoundParameters.ContainsKey('Overlay')) { $Overlay } else { [string]$config.defaultOverlay }
if ($overlayName -eq 'None') { $overlayName = '' }
$overlayFiles = @{}
$overlayExclude = @()
$updateExclude = @()
$overlayExcluded = [System.Collections.Generic.List[string]]::new()
if ($overlayName) {
    $overlayProperty = $config.overlays.PSObject.Properties[$overlayName]
    if (-not $overlayProperty) {
        $defined = @($config.overlays.PSObject.Properties | ForEach-Object { $_.Name })
        throw "Overlay '$overlayName' is not defined under overlays in the configuration (defined: $($defined -join ', ')). Use -Overlay None to deploy the upstream baseline only."
    }
    $overlayExclude = Get-StringList $overlayProperty.Value.exclude
    # Windows Update rings and driver profiles the overlay leaves out because something else
    # (such as an RMM tool) manages updates; -IncludeUpdatePolicies deploys them anyway.
    $updateExclude = Get-StringList $overlayProperty.Value.excludeUpdatePolicies
    if (-not $IncludeUpdatePolicies) { $overlayExclude = @($overlayExclude) + @($updateExclude) }
    elseif (-not $updateExclude) { Write-Warning "-IncludeUpdatePolicies has no effect: the $overlayName overlay doesn't leave out any update policies." }
    foreach ($entry in @($overlayProperty.Value.platforms.PSObject.Properties)) {
        if ($entry.Name -notin @($config.platforms.PSObject.Properties | ForEach-Object { $_.Name })) {
            throw "Overlay '$overlayName' has files for platform '$($entry.Name)', which is not a configured platform."
        }
        if ($entry.Name -notin $Platform) { continue }
        $overlayFolder = Join-Path $BaselinePath $entry.Value
        if (-not (Test-Path -LiteralPath $overlayFolder)) { throw "The $overlayName overlay folder '$overlayFolder' was not found." }
        $overlayFiles[$entry.Name] = @(foreach ($overlayFile in Get-ChildItem -LiteralPath $overlayFolder -Recurse -Filter *.json | Sort-Object Name) {
                $overlayJson = Read-JsonFile $overlayFile.FullName
                [pscustomobject]@{
                    File   = $overlayFile
                    Json   = $overlayJson
                    Name   = $overlayJson.($PolicyTypes[(Get-PolicyEndpoint $overlayJson)].NameProperty)
                    OibId  = Get-OibId $overlayJson
                    Used   = $false
                }
            })
    }
}

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

        # Overlay: leave the policy out, or swap in the overlay's version of it.
        $overlaySource = $null
        $sourceFile = $file
        if ($overlayExclude -and (Test-NameMatch $name $overlayExclude)) {
            $overlayExcluded.Add($name)
            continue
        }
        $oibId = Get-OibId $json
        $replacement = @($overlayFiles[$platformName] | Where-Object { ($oibId -and $_.OibId -eq $oibId) -or $_.Name -eq $name } | Select-Object -First 1)
        if ($replacement) {
            $replacement[0].Used = $true
            if ($replacement[0].Name -ne $name) {
                $problems.Add("The $overlayName overlay's '$($replacement[0].Name)' replaces the baseline's '$name', which has a different name or version. Upstream has probably updated the policy; update the overlay file.")
            }
            $sourceFile = $replacement[0].File
            $json = $replacement[0].Json
            $endpoint = Get-PolicyEndpoint $json
            $name = $replacement[0].Name
            $overlaySource = $overlayName
        }
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
        $audienceMatch = @($config.audiences | Where-Object { Test-NameMatch $name (Get-StringList $_.match) } | Select-Object -First 1)
        if (-not $audienceMatch) { $problems.Add("$($name): matches no audience in the configuration") }

        $allPolicies.Add([pscustomobject]@{
                Name          = $name
                OriginalName  = $originalName
                Overlay       = $overlaySource
                HybridRemoved = $hybridRemoved
                HybridReasons = $hybridReasons
                HybridEmpty   = $hybridEmpty
                Platform   = $platformName
                File       = $sourceFile.FullName
                Json       = $json
                Endpoint   = $endpoint
                Category   = if ($categoryMatch) { $categoryMatch[0].name } else { $null }
                Audience   = if ($audienceMatch) { $audienceMatch[0].name } else { $null }
                Rings      = if ($ringRule) { @((Get-StringList $ringRule[0].rings) | Where-Object { $_ -in $configRings }) } else { $configRings }
                Filter     = if ($filterRule) { $filterRule[0] } else { $null }
                SkipReason = if ($skipRule) { $skipRule[0].reason } else { $null }
                UnassignedReason = if ($ringRule) { $ringRule[0].reason } else { $null }
            })
    }
}
foreach ($platformName in $overlayFiles.Keys) {
    foreach ($unused in @($overlayFiles[$platformName] | Where-Object { -not $_.Used })) {
        $problems.Add("The $overlayName overlay's '$($unused.Name)' doesn't match any $platformName baseline policy by OIB ID or name. Upstream may have renamed or removed it; update the overlay.")
    }
}

if ($ExportMapping) {
    # Writes the full group and assignment plan as Markdown and stops; nothing is sent to Graph.
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
    if ($TestRingOnly) { $regenerate += ' -TestRingOnly' }
    if ($PSBoundParameters.ContainsKey('Overlay')) { $regenerate += " -Overlay $Overlay" }

    $lines.Add("# Update ring group and assignment mapping ($Environment)")
    $lines.Add('')
    $lines.Add("Generated from [``DeploymentConfig.json``](DeploymentConfig.json) and the $($Platform -join ' and ') baseline files by ``Deploy-OpenIntuneBaseline.ps1 -ExportMapping``, for the **$Environment** environment. Regenerate it after changing the configuration or updating the baseline:")
    $lines.Add('')
    $lines.Add('```powershell')
    $lines.Add($regenerate)
    $lines.Add('```')
    $lines.Add('')
    # A group set is one category and audience pair that has at least one deployed policy.
    $groupSets = @(foreach ($categoryName in $orderedCategories) {
            foreach ($audienceName in $audienceNames) {
                $count = @($deployed | Where-Object { $_.Category -eq $categoryName -and $_.Audience -eq $audienceName }).Count
                if ($count) { [pscustomobject]@{ Category = $categoryName; Audience = $audienceName; Count = $count } }
            }
        })

    $lines.Add("A default run deploys **$($deployed.Count) policies** into **$($orderedCategories.Count) categories**, creating **$($groupSets.Count * $configRings.Count) groups** and **$(@($config.filters).Count) filters**. Policies are only assigned to the rings named with ``-Ring`` in each run, so this is the full plan once every ring is rolled out.")
    $lines.Add('')

    $lines.Add('## Groups')
    $lines.Add('')
    $lines.Add('Each category gets a set of ring groups for each audience its policies target. Groups are only created for audiences a category actually uses.')
    $lines.Add('')
    $header = '| Category | Audience | Policies | ' + (($configRings | ForEach-Object { "Ring $_ group" }) -join ' | ') + ' |'
    $lines.Add($header)
    $lines.Add('| --- | --- | --- | ' + (($configRings | ForEach-Object { '---' }) -join ' | ') + ' |')
    foreach ($set in $groupSets) {
        $cells = $configRings | ForEach-Object { '`' + (Get-GroupName $set.Category $_ $set.Audience) + '`' }
        $lines.Add("| [$($set.Category)](#$(($set.Category.ToLower() -replace '[^a-z0-9 -]', '') -replace ' ', '-')) | $($set.Audience) | $($set.Count) | $($cells -join ' | ') |")
    }
    $lines.Add('')

    $lines.Add('### Ring membership')
    $lines.Add('')
    $lines.Add('Every category uses the same membership for a given ring and audience, so a device or user sits in the same ring for all categories. The categories still roll out independently, because each category is only assigned to the rings you name with `-Ring`.')
    $lines.Add('')
    $lines.Add('All groups are static by default. With the switch shown, rings that have a rule are created as dynamic groups instead.')
    $lines.Add('')
    $lines.Add('| Audience | Policies | Ring | Default | Dynamic rule (with the switch) |')
    $lines.Add('| --- | --- | --- | --- | --- |')
    foreach ($audience in @($config.audiences)) {
        $patterns = (Get-StringList $audience.match | ForEach-Object { '`' + $_ + '`' }) -join ', '
        foreach ($ringName in $configRings) {
            $rule = Get-ConfiguredRule $audience.name $ringName
            $dynamicText = if ($rule -and $audience.dynamicSwitch) { "``-$($audience.dynamicSwitch)``: ``$(Format-Cell $rule)``" } else { 'Always static' }
            $lines.Add("| $($audience.name) | $patterns | $ringName | Static | $dynamicText |")
        }
    }
    $lines.Add('')
    $lines.Add('An audience takes every policy matching its patterns that an earlier audience did not take.')
    $lines.Add('')

    if ($overlayName) {
        $lines.Add("## $overlayName overlay")
        $lines.Add('')
        $lines.Add("These are the differences from the upstream baseline, defined under ``overlays.$overlayName`` in the configuration. The upstream files are not changed. Deploy the upstream baseline instead with ``-Overlay None``.")
        $lines.Add('')
        $lines.Add('| Change | Policy | Source |')
        $lines.Add('| --- | --- | --- |')
        foreach ($policy in @($allPolicies | Where-Object Overlay | Sort-Object Name)) {
            $relative = [IO.Path]::GetRelativePath($BaselinePath, $policy.File).Replace('\', '/')
            $lines.Add("| Replaced with the $overlayName version | $(Format-Cell $policy.Name) | ``$(Format-Cell $relative)`` |")
        }
        foreach ($excludedName in @($overlayExcluded | Sort-Object)) {
            $reason = if ($updateExclude -and (Test-NameMatch $excludedName $updateExclude)) { '`excludeUpdatePolicies` in the configuration; deploy with `-IncludeUpdatePolicies`' } else { '`exclude` in the configuration' }
            $lines.Add("| Left out | $(Format-Cell $excludedName) | $reason |")
        }
        $lines.Add('')
    }

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
        foreach ($set in @($groupSets | Where-Object Category -eq $categoryName)) {
            $lines.Add("$($set.Audience) groups: $(($configRings | ForEach-Object { '`' + (Get-GroupName $categoryName $_ $set.Audience) + '`' }) -join ', ')")
            $lines.Add('')
        }
        $lines.Add('| Policy | Type | Scope | Assigned to | Rings | Filter |')
        $lines.Add('| --- | --- | --- | --- | --- | --- |')
        foreach ($policy in @($allPolicies | Where-Object { $_.Category -eq $categoryName } | Sort-Object Name)) {
            $name = Format-Cell $policy.Name
            if ($policy.HybridEmpty) { $name = "~~$name~~ *(not deployed in hybrid: all settings removed)*" }
            elseif ($policy.SkipReason) { $name = "~~$name~~ *(skipped by default)*" }
            if ($policy.Overlay -and -not $policy.HybridEmpty) { $name += " *($($policy.Overlay))*" }
            $rings = if (@($policy.Rings).Count) { $policy.Rings -join ', ' } else { '*Not assigned*' }
            $filterText = if ($policy.Filter) { "$($policy.Filter.mode) ``$($filtersByKey[$policy.Filter.filter].displayName)``" } else { '' }
            $lines.Add("| $name | $(Get-PolicyTypeLabel $policy) | $(Get-PolicyScope $policy.Name) | $($policy.Audience) | $rings | $filterText |")
        }
        $lines.Add('')
    }

    $heldBack = @($deployed | Where-Object { $_.UnassignedReason -and -not @($_.Rings).Count } | Sort-Object Name)
    if ($heldBack) {
        $lines.Add('## Created but not assigned')
        $lines.Add('')
        $lines.Add('These are created in every run but left unassigned by `ringSpecificPolicies`, so you can assign them by hand when ready.')
        $lines.Add('')
        $lines.Add('| Policy | Reason |')
        $lines.Add('| --- | --- |')
        foreach ($policy in $heldBack) { $lines.Add("| $(Format-Cell $policy.Name) | $(Format-Cell $policy.UnassignedReason) |") }
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
# Conflict pairs use the baseline's own names, without the hybrid suffix. Two conflicting
# policies can both be created; they only clash when assigned to the same ring group, so a
# policy left unassigned by ringSpecificPolicies (or with -SkipAssignments) never conflicts.
$assignedPolicies = @(if (-not $SkipAssignments) { $policies | Where-Object { @($_.Rings).Count } })
$reported = @{}
foreach ($pair in $conflictPairs) {
    foreach ($first in @($assignedPolicies | Where-Object { $_.OriginalName -like $pair[0] })) {
        foreach ($second in @($assignedPolicies | Where-Object { $_.OriginalName -like $pair[1] })) {
            $sharedRings = @($first.Rings | Where-Object { $_ -in $second.Rings })
            if (-not $sharedRings) { continue }
            $key = (@($first.OriginalName, $second.OriginalName) | Sort-Object) -join '|'
            if ($reported.ContainsKey($key)) { continue }
            $reported[$key] = $true
            $problems.Add("'$($first.OriginalName)' conflicts with '$($second.OriginalName)' and both would be assigned to ring $($sharedRings -join ', '). Leave one of them unassigned with ringSpecificPolicies, or use -PolicyName to deploy only one.")
        }
    }
}

if ($problems.Count) { throw "The configuration has problems, nothing was changed:`n  $($problems -join "`n  ")" }

$neededCategories = @($policies | ForEach-Object { $_.Category } | Sort-Object -Unique)
$neededFilterKeys = @($policies | Where-Object Filter | ForEach-Object { $_.Filter.filter } | Sort-Object -Unique)
# One set of ring groups per category and audience that the selected policies use.
$neededGroupSets = @($policies | ForEach-Object { [pscustomobject]@{ Category = $_.Category; Audience = $_.Audience } } |
        Sort-Object Category, Audience -Unique)
$groupCount = $neededGroupSets.Count * $configRings.Count

Write-Host "Environment: $Environment"
if ($overlayName) {
    $replacedCount = @($allPolicies | Where-Object Overlay).Count
    Write-Host "Overlay: $overlayName - $replacedCount policies replaced with $overlayName versions, $($overlayExcluded.Count) left out. Use -Overlay None for the upstream baseline only."
    if ($updateExclude) {
        if ($IncludeUpdatePolicies) { Write-Host 'Update policies: included (-IncludeUpdatePolicies)' }
        else { Write-Host 'Update policies: left out (Windows Update rings and drivers). Use -IncludeUpdatePolicies if the RMM tool does not manage updates.' }
    }
}
else { Write-Host 'Overlay: none (upstream baseline only)' }
if ($Environment -eq 'Hybrid') {
    $changed = @($policies | Where-Object { $_.HybridRemoved.Count })
    Write-Host "Removed $(@($changed | ForEach-Object { $_.HybridRemoved }).Count) settings from $($changed.Count) policies for on-premises AD compatibility."
}
Write-Host "Loaded $($policies.Count) policies in $($neededCategories.Count) categories, which need $groupCount groups and $($neededFilterKeys.Count) filters."
if ($SkipAssignments) { Write-Host 'Assignments are skipped (-SkipAssignments).' }
else { Write-Host "Rings to assign in this run: $($Ring -join ', ')" }
if ($TestRingOnly) { Write-Host "Test ring only: creating just the $($configRings[0]) groups (static) and assigning every policy to them." }
elseif ($script:DynamicAudiences) { Write-Host "Dynamic ring groups: $($script:DynamicAudiences -join ', ') (rings with a rule; the rest are static)" }
else { Write-Host 'Ring groups: all static' }

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
foreach ($set in $neededGroupSets) {
    $categoryName = $set.Category
    $audienceName = $set.Audience
    foreach ($ringName in $configRings) {
        $name = Get-GroupName $categoryName $ringName $audienceName
        $key = "$categoryName|$ringName|$audienceName"
        $rule = Get-RingRule $audienceName $ringName
        $description = if ($rule) {
            "OpenIntuneBaseline update ring $ringName for $categoryName policies targeting $($audienceName.ToLower()). Members are added automatically by the dynamic membership rule."
        }
        else {
            "OpenIntuneBaseline update ring $ringName for $categoryName policies targeting $($audienceName.ToLower()). Add $($audienceName.ToLower()) to roll the policies out to them."
        }
        try {
            $existing = Get-GraphCollection "$GraphV1/groups?`$select=id,displayName,securityEnabled,groupTypes,membershipRule&`$filter=$(Get-EscapedFilter 'displayName' $name)"
            if ($existing.Count -gt 1) { throw "$($existing.Count) groups in the tenant have this name, so the right one is unclear." }
            if ($existing.Count -eq 1) {
                $group = $existing[0]
                if (-not $group.securityEnabled) { throw 'A group with this name exists but is not security enabled, so it cannot be assigned.' }
                $groupMap[$key] = $group.id
                $isDynamic = 'DynamicMembership' -in @($group.groupTypes)

                $difference = if ($rule -and -not $isDynamic) { 'is static but configured as dynamic' }
                elseif ($rule -and (Format-Rule $group.membershipRule) -ne (Format-Rule $rule)) { 'has a different dynamic rule from the configuration' }
                elseif (-not $rule -and $isDynamic) { 'is dynamic but configured as static' }

                if (-not $difference) {
                    Add-Result 'Group' $name 'Exists' $group.id
                    continue
                }
                if (-not $UpdateGroupRules) {
                    Add-Result 'Group' $name 'Exists' $group.id "The group $difference. Run with -UpdateGroupRules to apply the configuration."
                    continue
                }

                if ($rule) {
                    if (-not $isDynamic) {
                        # Making a group dynamic removes its direct members, so refuse rather than drop them silently.
                        $members = @((Invoke-Graph -Method GET -Uri "$GraphV1/groups/$($group.id)/members?`$select=id&`$top=1").value)
                        if ($members.Count) { throw 'The group has members, which converting it to dynamic would remove. Empty it first, or leave it static.' }
                    }
                    $body = [ordered]@{
                        description                   = $description
                        groupTypes                    = @(@($group.groupTypes) + 'DynamicMembership' | Sort-Object -Unique)
                        membershipRule                = $rule
                        membershipRuleProcessingState = 'On'
                    }
                    $action = 'Apply the dynamic membership rule'
                    $done = 'applied the configured rule'
                }
                else {
                    # Making a group static keeps its current members as ordinary members.
                    $body = [ordered]@{
                        description = $description
                        groupTypes  = @(@($group.groupTypes) | Where-Object { $_ -ne 'DynamicMembership' })
                    }
                    $action = 'Convert to a static group'
                    $done = 'converted it to static; its current members were kept'
                }
                Write-Verbose "Group update body: $($body | ConvertTo-Json -Depth 10)"
                if ($PSCmdlet.ShouldProcess($name, $action)) {
                    $null = Invoke-Graph -Method PATCH -Uri "$GraphV1/groups/$($group.id)" -Body $body
                    Add-Result 'Group' $name 'Updated' $group.id "The group $difference; $done."
                }
                else {
                    Add-Result 'Group' $name 'WhatIf' $group.id "The group $difference; would have $done."
                }
                continue
            }

            $body = [ordered]@{
                displayName     = $name
                description     = $description
                mailEnabled     = $false
                mailNickname    = 'oib-' + [guid]::NewGuid().ToString('N').Substring(0, 10)
                securityEnabled = $true
                groupTypes      = @()
            }
            if ($rule) {
                $body.groupTypes = @('DynamicMembership')
                $body.membershipRule = $rule
                $body.membershipRuleProcessingState = 'On'
            }
            Write-Verbose "Group body: $($body | ConvertTo-Json -Depth 10)"

            if ($PSCmdlet.ShouldProcess($name, $(if ($rule) { 'Create dynamic group' } else { 'Create group' }))) {
                $created = Invoke-Graph -Method POST -Uri "$GraphV1/groups" -Body $body
                $groupMap[$key] = $created.id
                $script:CreatedDirectoryObjects = $true
                Add-Result 'Group' $name 'Created' $created.id $(if ($rule) { 'Dynamic' } else { 'Static' })
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
        $unassignedDetail = if ($policy.UnassignedReason) { "Left unassigned by ringSpecificPolicies: $($policy.UnassignedReason)" } else { 'Left unassigned by ringSpecificPolicies.' }
        Add-Result 'Assignment' $name 'Unassigned' $policyId $unassignedDetail
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
            $groupId = $groupMap["$($policy.Category)|$ringName|$($policy.Audience)"]
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
    Write-Host ''
    foreach ($audienceName in @($neededGroupSets | ForEach-Object { $_.Audience } | Sort-Object -Unique)) {
        $staticRings = @($Ring | Where-Object { -not (Get-RingRule $audienceName $_) })
        $dynamicRings = @($Ring | Where-Object { Get-RingRule $audienceName $_ })
        if ($staticRings) { Write-Host "Add $($audienceName.ToLower()) to the ring $($staticRings -join ', ') $audienceName groups to roll the policies out to them." }
        if ($dynamicRings) { Write-Host "The ring $($dynamicRings -join ', ') $audienceName groups are dynamic and fill automatically. Entra ID can take a while to process new rules." }
    }
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
