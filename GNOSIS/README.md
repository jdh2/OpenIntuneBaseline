# Gnosis overlay

Gnosis's versions of OpenIntuneBaseline policies. [`Deploy-OpenIntuneBaseline.ps1`](../Deploy-OpenIntuneBaseline.ps1) applies them on top of the upstream baseline by default; the upstream `WINDOWS` folder stays identical to [SkipToTheEndpoint/OpenIntuneBaseline](https://github.com/SkipToTheEndpoint/OpenIntuneBaseline) so it can be updated from there.

| File | Differs from upstream by |
| --- | --- |
| `Windows/SettingsCatalog/Win - OIB - ES - Windows LAPS - D - LAPS Configuration - v4.0.json` | `automaticaccountmanagementnameorprefix`: `""` → `"Gnosis"` |
| `Windows/SettingsCatalog/Win - OIB - ES - Local Group Membership - D - Local Administrators - v3.7.json` | Administrators group member: `"WLapsAdmin"` → `"Gnosis"` |

The Windows Update rings and driver profiles are left out through `overlays.Gnosis.excludeUpdatePolicies` in [`Deployment/DeploymentConfig.json`](../Deployment/DeploymentConfig.json), because ConnectWise RMM manages Windows updates. For a tenant where it doesn't, deploy them with `-IncludeUpdatePolicies`.

## When upstream releases a new version

The deployment script stops if a file here no longer lines up with upstream (upstream renamed, re-versioned or removed the policy). To update a file:

1. Copy upstream's new version from `WINDOWS/IntuneManagement/...` into `Windows/SettingsCatalog/` and delete the old one.
2. Re-apply the one-value change from the table above. Edit only that value; don't re-export from Intune.
3. Regenerate the mapping: `.\Deploy-OpenIntuneBaseline.ps1 -ExportMapping .\Deployment\MAPPING.md`.

Keep these files in a folder whose path doesn't contain `IntuneManagement`: the repo's `.gitattributes` treats those folders as UTF-16 and would garble these UTF-8 files.
