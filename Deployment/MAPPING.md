# Update ring group and assignment mapping (CloudNative)

Generated from [`DeploymentConfig.json`](DeploymentConfig.json) and the Windows and Windows365 baseline files by `Deploy-OpenIntuneBaseline.ps1 -ExportMapping`, for the **CloudNative** environment. Regenerate it after changing the configuration or updating the baseline:

```powershell
.\Deploy-OpenIntuneBaseline.ps1 -ExportMapping .\Deployment\MAPPING.md
```

A default run deploys **78 policies** into **10 categories**, creating **64 groups** and **2 filters**. Policies are only assigned to the rings named with `-Ring` in each run, so this is the full plan once every ring is rolled out.

## Groups

Each category gets a set of ring groups for each audience its policies target. Groups are only created for audiences a category actually uses.

| Category | Audience | Policies | Ring Test group | Ring 1 group | Ring 2 group | Ring 3 group |
| --- | --- | --- | --- | --- | --- | --- |
| [Windows 365](#windows-365) | Users | 1 | `Windows 365 - Update Ring - Test - Users` | `Windows 365 - Update Ring - 1 - Users` | `Windows 365 - Update Ring - 2 - Users` | `Windows 365 - Update Ring - 3 - Users` |
| [Windows 365](#windows-365) | Devices | 2 | `Windows 365 - Update Ring - Test - Devices` | `Windows 365 - Update Ring - 1 - Devices` | `Windows 365 - Update Ring - 2 - Devices` | `Windows 365 - Update Ring - 3 - Devices` |
| [Device Compliance](#device-compliance) | Users | 9 | `Device Compliance - Update Ring - Test - Users` | `Device Compliance - Update Ring - 1 - Users` | `Device Compliance - Update Ring - 2 - Users` | `Device Compliance - Update Ring - 3 - Users` |
| [Microsoft Office](#microsoft-office) | Users | 2 | `Microsoft Office - Update Ring - Test - Users` | `Microsoft Office - Update Ring - 1 - Users` | `Microsoft Office - Update Ring - 2 - Users` | `Microsoft Office - Update Ring - 3 - Users` |
| [Microsoft Office](#microsoft-office) | Devices | 2 | `Microsoft Office - Update Ring - Test - Devices` | `Microsoft Office - Update Ring - 1 - Devices` | `Microsoft Office - Update Ring - 2 - Devices` | `Microsoft Office - Update Ring - 3 - Devices` |
| [Microsoft Edge](#microsoft-edge) | Users | 5 | `Microsoft Edge - Update Ring - Test - Users` | `Microsoft Edge - Update Ring - 1 - Users` | `Microsoft Edge - Update Ring - 2 - Users` | `Microsoft Edge - Update Ring - 3 - Users` |
| [Microsoft Edge](#microsoft-edge) | Devices | 2 | `Microsoft Edge - Update Ring - Test - Devices` | `Microsoft Edge - Update Ring - 1 - Devices` | `Microsoft Edge - Update Ring - 2 - Devices` | `Microsoft Edge - Update Ring - 3 - Devices` |
| [Microsoft OneDrive](#microsoft-onedrive) | Users | 1 | `Microsoft OneDrive - Update Ring - Test - Users` | `Microsoft OneDrive - Update Ring - 1 - Users` | `Microsoft OneDrive - Update Ring - 2 - Users` | `Microsoft OneDrive - Update Ring - 3 - Users` |
| [Microsoft OneDrive](#microsoft-onedrive) | Devices | 1 | `Microsoft OneDrive - Update Ring - Test - Devices` | `Microsoft OneDrive - Update Ring - 1 - Devices` | `Microsoft OneDrive - Update Ring - 2 - Devices` | `Microsoft OneDrive - Update Ring - 3 - Devices` |
| [Microsoft Defender](#microsoft-defender) | Devices | 7 | `Microsoft Defender - Update Ring - Test - Devices` | `Microsoft Defender - Update Ring - 1 - Devices` | `Microsoft Defender - Update Ring - 2 - Devices` | `Microsoft Defender - Update Ring - 3 - Devices` |
| [Encryption](#encryption) | Devices | 1 | `Encryption - Update Ring - Test - Devices` | `Encryption - Update Ring - 1 - Devices` | `Encryption - Update Ring - 2 - Devices` | `Encryption - Update Ring - 3 - Devices` |
| [Identity and Access](#identity-and-access) | Devices | 6 | `Identity and Access - Update Ring - Test - Devices` | `Identity and Access - Update Ring - 1 - Devices` | `Identity and Access - Update Ring - 2 - Devices` | `Identity and Access - Update Ring - 3 - Devices` |
| [Windows Security](#windows-security) | Users | 4 | `Windows Security - Update Ring - Test - Users` | `Windows Security - Update Ring - 1 - Users` | `Windows Security - Update Ring - 2 - Users` | `Windows Security - Update Ring - 3 - Users` |
| [Windows Security](#windows-security) | Devices | 27 | `Windows Security - Update Ring - Test - Devices` | `Windows Security - Update Ring - 1 - Devices` | `Windows Security - Update Ring - 2 - Devices` | `Windows Security - Update Ring - 3 - Devices` |
| [Windows Experience](#windows-experience) | Users | 2 | `Windows Experience - Update Ring - Test - Users` | `Windows Experience - Update Ring - 1 - Users` | `Windows Experience - Update Ring - 2 - Users` | `Windows Experience - Update Ring - 3 - Users` |
| [Windows Experience](#windows-experience) | Devices | 6 | `Windows Experience - Update Ring - Test - Devices` | `Windows Experience - Update Ring - 1 - Devices` | `Windows Experience - Update Ring - 2 - Devices` | `Windows Experience - Update Ring - 3 - Devices` |

### Ring membership

Every category uses the same membership for a given ring and audience, so a device or user sits in the same ring for all categories. The categories still roll out independently, because each category is only assigned to the rings you name with `-Ring`.

All groups are static by default. With the switch shown, rings that have a rule are created as dynamic groups instead.

| Audience | Policies | Ring | Default | Dynamic rule (with the switch) |
| --- | --- | --- | --- | --- |
| Users | `* - U - *` | Test | Static | Always static |
| Users | `* - U - *` | 1 | Static | `-DynamicUserRings`: `(user.accountEnabled -eq true) and (user.userType -eq "Member") and ((user.objectId -startsWith "0") or (user.objectId -startsWith "1") or (user.objectId -startsWith "2") or (user.objectId -startsWith "3") or (user.objectId -startsWith "4"))` |
| Users | `* - U - *` | 2 | Static | `-DynamicUserRings`: `(user.accountEnabled -eq true) and (user.userType -eq "Member") and ((user.objectId -startsWith "5") or (user.objectId -startsWith "6") or (user.objectId -startsWith "7") or (user.objectId -startsWith "8") or (user.objectId -startsWith "9"))` |
| Users | `* - U - *` | 3 | Static | `-DynamicUserRings`: `(user.accountEnabled -eq true) and (user.userType -eq "Member") and ((user.objectId -startsWith "a") or (user.objectId -startsWith "b") or (user.objectId -startsWith "c") or (user.objectId -startsWith "d") or (user.objectId -startsWith "e") or (user.objectId -startsWith "f"))` |
| Devices | `*` | Test | Static | Always static |
| Devices | `*` | 1 | Static | `-DynamicDeviceRings`: `(device.deviceOSType -eq "Windows") and (device.managementType -eq "MDM") and ((device.deviceId -startsWith "0") or (device.deviceId -startsWith "1") or (device.deviceId -startsWith "2") or (device.deviceId -startsWith "3") or (device.deviceId -startsWith "4"))` |
| Devices | `*` | 2 | Static | `-DynamicDeviceRings`: `(device.deviceOSType -eq "Windows") and (device.managementType -eq "MDM") and ((device.deviceId -startsWith "5") or (device.deviceId -startsWith "6") or (device.deviceId -startsWith "7") or (device.deviceId -startsWith "8") or (device.deviceId -startsWith "9"))` |
| Devices | `*` | 3 | Static | `-DynamicDeviceRings`: `(device.deviceOSType -eq "Windows") and (device.managementType -eq "MDM") and ((device.deviceId -startsWith "a") or (device.deviceId -startsWith "b") or (device.deviceId -startsWith "c") or (device.deviceId -startsWith "d") or (device.deviceId -startsWith "e") or (device.deviceId -startsWith "f"))` |

An audience takes every policy matching its patterns that an earlier audience did not take.

## Filters

| Filter | Rule | Applied to |
| --- | --- | --- |
| `OIB - Windows - Windows 365 Cloud PCs` | `(device.model -startsWith "Cloud PC")` | include: Win365 - OIB - Compliance - U - Device Health - v1.0<br>include: Win365 - OIB - Device Security - D - Connectivity Settings - v1.0<br>include: Win365 - OIB - Device Security - D - Resource Redirection - v1.0 |
| `OIB - Windows - Virtual Machines` | `(device.model -startsWith "Cloud PC") or (device.model -contains "Virtual") or (device.model -startsWith "VMware") or (device.operatingSystemSKU -eq "ServerRdsh")` | exclude: Win - OIB - CP - Device Health - U - BitLocker - v4.0<br>exclude: Win - OIB - CP - Device Health - U - Code Integrity - v4.0<br>exclude: Win - OIB - CP - Device Health - U - SecureBoot - v4.0<br>exclude: Win - OIB - ES - Encryption - D - BitLocker (OS Disk) - v3.7 |

## Policies by category

**Rings** lists the ring groups a policy is assigned to once those rings are rolled out. Policies marked *Not assigned* are created but left unassigned, as set in `ringSpecificPolicies`.

### Windows 365

Users groups: `Windows 365 - Update Ring - Test - Users`, `Windows 365 - Update Ring - 1 - Users`, `Windows 365 - Update Ring - 2 - Users`, `Windows 365 - Update Ring - 3 - Users`

Devices groups: `Windows 365 - Update Ring - Test - Devices`, `Windows 365 - Update Ring - 1 - Devices`, `Windows 365 - Update Ring - 2 - Devices`, `Windows 365 - Update Ring - 3 - Devices`

| Policy | Type | Scope | Assigned to | Rings | Filter |
| --- | --- | --- | --- | --- | --- |
| Win365 - OIB - Compliance - U - Device Health - v1.0 | Compliance | User | Users | Test, 1, 2, 3 | include `OIB - Windows - Windows 365 Cloud PCs` |
| Win365 - OIB - Device Security - D - Connectivity Settings - v1.0 | Settings catalog | Device | Devices | Test, 1, 2, 3 | include `OIB - Windows - Windows 365 Cloud PCs` |
| Win365 - OIB - Device Security - D - Resource Redirection - v1.0 | Settings catalog | Device | Devices | Test, 1, 2, 3 | include `OIB - Windows - Windows 365 Cloud PCs` |

### Device Compliance

Users groups: `Device Compliance - Update Ring - Test - Users`, `Device Compliance - Update Ring - 1 - Users`, `Device Compliance - Update Ring - 2 - Users`, `Device Compliance - Update Ring - 3 - Users`

| Policy | Type | Scope | Assigned to | Rings | Filter |
| --- | --- | --- | --- | --- | --- |
| Win - OIB - CP - Defender - U - Real-Time Protection - v4.0 | Compliance | User | Users | Test, 1, 2, 3 |  |
| Win - OIB - CP - Defender - U - Security Intelligence - v4.0 | Compliance | User | Users | Test, 1, 2, 3 |  |
| Win - OIB - CP - Device Health - U - BitLocker - v4.0 | Compliance | User | Users | Test, 1, 2, 3 | exclude `OIB - Windows - Virtual Machines` |
| Win - OIB - CP - Device Health - U - Code Integrity - v4.0 | Compliance | User | Users | Test, 1, 2, 3 | exclude `OIB - Windows - Virtual Machines` |
| Win - OIB - CP - Device Health - U - SecureBoot - v4.0 | Compliance | User | Users | Test, 1, 2, 3 | exclude `OIB - Windows - Virtual Machines` |
| Win - OIB - CP - Device Security - U - Antispyware - v4.0 | Compliance | User | Users | Test, 1, 2, 3 |  |
| Win - OIB - CP - Device Security - U - Antivirus - v4.0 | Compliance | User | Users | Test, 1, 2, 3 |  |
| Win - OIB - CP - Device Security - U - Firewall - v4.0 | Compliance | User | Users | Test, 1, 2, 3 |  |
| Win - OIB - CP - Device Security - U - TPM - v4.0 | Compliance | User | Users | Test, 1, 2, 3 |  |

### Microsoft Office

Users groups: `Microsoft Office - Update Ring - Test - Users`, `Microsoft Office - Update Ring - 1 - Users`, `Microsoft Office - Update Ring - 2 - Users`, `Microsoft Office - Update Ring - 3 - Users`

Devices groups: `Microsoft Office - Update Ring - Test - Devices`, `Microsoft Office - Update Ring - 1 - Devices`, `Microsoft Office - Update Ring - 2 - Devices`, `Microsoft Office - Update Ring - 3 - Devices`

| Policy | Type | Scope | Assigned to | Rings | Filter |
| --- | --- | --- | --- | --- | --- |
| Win - OIB - SC - Microsoft Office - D - Security - v3.6 | Settings catalog | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - SC - Microsoft Office - D - Updates - v3.0 | Settings catalog | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - SC - Microsoft Office - U - Config and Experience - v3.6 | Settings catalog | User | Users | Test, 1, 2, 3 |  |
| Win - OIB - SC - Microsoft Office - U - Security - v4.0 | Settings catalog | User | Users | Test, 1, 2, 3 |  |

### Microsoft Edge

Users groups: `Microsoft Edge - Update Ring - Test - Users`, `Microsoft Edge - Update Ring - 1 - Users`, `Microsoft Edge - Update Ring - 2 - Users`, `Microsoft Edge - Update Ring - 3 - Users`

Devices groups: `Microsoft Edge - Update Ring - Test - Devices`, `Microsoft Edge - Update Ring - 1 - Devices`, `Microsoft Edge - Update Ring - 2 - Devices`, `Microsoft Edge - Update Ring - 3 - Devices`

| Policy | Type | Scope | Assigned to | Rings | Filter |
| --- | --- | --- | --- | --- | --- |
| Win - OIB - SC - Microsoft Edge - D - Security - v4.0 | Settings catalog | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - SC - Microsoft Edge - D - Updates - v4.0 | Settings catalog | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - SC - Microsoft Edge - U - Extensions - v3.1 | Settings catalog | User | Users | Test, 1, 2, 3 |  |
| Win - OIB - SC - Microsoft Edge - U - Management - v4.0 | Settings catalog | User | Users | Test, 1, 2, 3 |  |
| Win - OIB - SC - Microsoft Edge - U - Password Management - v3.0 | Settings catalog | User | Users | Test, 1, 2, 3 |  |
| Win - OIB - SC - Microsoft Edge - U - Profiles, Sign-In and Sync - v4.0 | Settings catalog | User | Users | Test, 1, 2, 3 |  |
| Win - OIB - SC - Microsoft Edge - U - User Experience - v4.0 | Settings catalog | User | Users | Test, 1, 2, 3 |  |

### Microsoft OneDrive

Users groups: `Microsoft OneDrive - Update Ring - Test - Users`, `Microsoft OneDrive - Update Ring - 1 - Users`, `Microsoft OneDrive - Update Ring - 2 - Users`, `Microsoft OneDrive - Update Ring - 3 - Users`

Devices groups: `Microsoft OneDrive - Update Ring - Test - Devices`, `Microsoft OneDrive - Update Ring - 1 - Devices`, `Microsoft OneDrive - Update Ring - 2 - Devices`, `Microsoft OneDrive - Update Ring - 3 - Devices`

| Policy | Type | Scope | Assigned to | Rings | Filter |
| --- | --- | --- | --- | --- | --- |
| Win - OIB - SC - Microsoft OneDrive - D - Configuration - v3.2 | Settings catalog | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - SC - Microsoft OneDrive - U - Configuration - v3.8 | Settings catalog | User | Users | Test, 1, 2, 3 |  |

### Microsoft Defender

Devices groups: `Microsoft Defender - Update Ring - Test - Devices`, `Microsoft Defender - Update Ring - 1 - Devices`, `Microsoft Defender - Update Ring - 2 - Devices`, `Microsoft Defender - Update Ring - 3 - Devices`

| Policy | Type | Scope | Assigned to | Rings | Filter |
| --- | --- | --- | --- | --- | --- |
| Win - OIB - ES - Attack Surface Reduction - D - ASR Rules (Audit Mode) - v3.1 | Endpoint security | Device | Devices | Test, 1, 2, 3 |  |
| ~~Win - OIB - ES - Attack Surface Reduction - D - ASR Rules (L2) - v3.7~~ *(skipped by default)* | Endpoint security | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - ES - Defender Antivirus - D - AV Configuration - v4.0 | Endpoint security | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - ES - Defender Antivirus - D - Security Experience - v4.0 | Endpoint security | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - ES - Defender Antivirus Updates - Ring 1 - Pilot - v3.4 | Endpoint security | Device | Devices | *Not assigned* |  |
| Win - OIB - ES - Defender Antivirus Updates - Ring 2 - UAT - v3.4 | Endpoint security | Device | Devices | *Not assigned* |  |
| Win - OIB - ES - Defender Antivirus Updates - Ring 3 - Production - v3.4 | Endpoint security | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - SC - Defender Antivirus - D - Additional Configuration - v4.0 | Settings catalog | Device | Devices | Test, 1, 2, 3 |  |

### Encryption

Devices groups: `Encryption - Update Ring - Test - Devices`, `Encryption - Update Ring - 1 - Devices`, `Encryption - Update Ring - 2 - Devices`, `Encryption - Update Ring - 3 - Devices`

| Policy | Type | Scope | Assigned to | Rings | Filter |
| --- | --- | --- | --- | --- | --- |
| Win - OIB - ES - Encryption - D - BitLocker (OS Disk) - v3.7 | Endpoint security | Device | Devices | Test, 1, 2, 3 | exclude `OIB - Windows - Virtual Machines` |
| ~~Win - OIB - ES - Encryption - U - Personal Data Encryption - v3.4~~ *(skipped by default)* | Endpoint security | User | Users | Test, 1, 2, 3 |  |

### Identity and Access

Devices groups: `Identity and Access - Update Ring - Test - Devices`, `Identity and Access - Update Ring - 1 - Devices`, `Identity and Access - Update Ring - 2 - Devices`, `Identity and Access - Update Ring - 3 - Devices`

| Policy | Type | Scope | Assigned to | Rings | Filter |
| --- | --- | --- | --- | --- | --- |
| Win - OIB - ES - Local Group Membership - D - Local Administrators - v3.7 | Endpoint security | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - ES - Windows Hello for Business - D - WHfB Configuration - v3.2 | Endpoint security | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - ES - Windows LAPS - D - LAPS Configuration - v4.0 | Endpoint security | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - SC - Credential Management - D - Passwordless - v3.3 | Settings catalog | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - SC - Microsoft Accounts - D - Configuration - v3.2 | Settings catalog | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - SC - Windows Hello for Business - D - Cloud Kerberos Trust - v3.5 | Settings catalog | Device | Devices | Test, 1, 2, 3 |  |

### Windows Security

Users groups: `Windows Security - Update Ring - Test - Users`, `Windows Security - Update Ring - 1 - Users`, `Windows Security - Update Ring - 2 - Users`, `Windows Security - Update Ring - 3 - Users`

Devices groups: `Windows Security - Update Ring - Test - Devices`, `Windows Security - Update Ring - 1 - Devices`, `Windows Security - Update Ring - 2 - Devices`, `Windows Security - Update Ring - 3 - Devices`

| Policy | Type | Scope | Assigned to | Rings | Filter |
| --- | --- | --- | --- | --- | --- |
| Win - OIB - ES - Windows Firewall - D - Firewall Configuration - v3.1 | Endpoint security | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - ES - Windows Firewall - D - Security Rules - v3.8 | Endpoint security | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - D - Administrator Protection - v4.0.1 | Settings catalog | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - D - Audit and Event Logging - v4.0 | Settings catalog | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - D - Config Refresh - v3.2 | Settings catalog | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - D - Enhanced Phishing Protection - v3.0 | Settings catalog | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - D - Local Security Policies - v4.0 | Settings catalog | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - D - Location and Privacy - v3.2 | Settings catalog | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - D - Login and Lock Screen - v3.8 | Settings catalog | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - D - Printing - v3.7 | Settings catalog | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - D - Remote Desktop Services and RPC - v3.0 | Settings catalog | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - D - Script File Associations - v4.0 | Settings catalog | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - D - Security Hardening - v4.0 | Settings catalog | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - D - Timezone - v3.4 | Settings catalog | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - D - User Rights - v3.7 | Settings catalog | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - D - Windows Package Manager - v3.5 | Settings catalog | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - D - Windows Subsystem for Linux - v3.2 | Settings catalog | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - U - Device Guard, Credential Guard and HVCI - v3.7 | Settings catalog | User | Users | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - U - Power and Device Lock - v4.0 | Settings catalog | User | Users | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - U - Windows Sandbox - v3.4 | Settings catalog | User | Users | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - U - Windows Spotlight and Org Messages - v3.0 | Settings catalog | User | Users | Test, 1, 2, 3 |  |
| Win - OIB - SC - Internet Explorer (Legacy) - D - Security - v4.0 | Settings catalog | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - SC - Network Security - D - Disable NTLM - v3.8 | Settings catalog | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - SC - Windows Update for Business - D - Delivery Optimisation - v3.0 | Settings catalog | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - SC - Windows Update for Business - D - Reports and Telemetry - v3.0 | Settings catalog | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - WUfB - Ring 1 - Pilot - v3.0 | Update ring | Device | Devices | *Not assigned* |  |
| Win - OIB - WUfB - Ring 2 - UAT - v3.0 | Update ring | Device | Devices | *Not assigned* |  |
| Win - OIB - WUfB - Ring 3 - Production - v3.0 | Update ring | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - WUfB Drivers - Ring 1 - Pilot - v3.0 | Driver updates | Device | Devices | *Not assigned* |  |
| Win - OIB - WUfB Drivers - Ring 2 - UAT - v3.0 | Driver updates | Device | Devices | *Not assigned* |  |
| Win - OIB - WUfB Drivers - Ring 3 - Production - v3.0 | Driver updates | Device | Devices | Test, 1, 2, 3 |  |

### Windows Experience

Users groups: `Windows Experience - Update Ring - Test - Users`, `Windows Experience - Update Ring - 1 - Users`, `Windows Experience - Update Ring - 2 - Users`, `Windows Experience - Update Ring - 3 - Users`

Devices groups: `Windows Experience - Update Ring - Test - Devices`, `Windows Experience - Update Ring - 1 - Devices`, `Windows Experience - Update Ring - 2 - Devices`, `Windows Experience - Update Ring - 3 - Devices`

| Policy | Type | Scope | Assigned to | Rings | Filter |
| --- | --- | --- | --- | --- | --- |
| Win - OIB - SC - Microsoft Store - D - Configuration - v3.8 | Settings catalog | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - SC - Microsoft Store - U - Configuration - v3.3 | Settings catalog | User | Users | Test, 1, 2, 3 |  |
| Win - OIB - SC - Windows Apps - D - In-Box App Removal - v4.0 | Settings catalog | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - SC - Windows User Experience - D - Automatic Restart Sign-On - v3.8 | Settings catalog | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - SC - Windows User Experience - D - Feature Configuration - v4.0 | Settings catalog | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - SC - Windows User Experience - D - Settings Sync - v3.7 | Settings catalog | Device | Devices | Test, 1, 2, 3 |  |
| Win - OIB - SC - Windows User Experience - U - Copilot - v3.8 | Settings catalog | User | Users | Test, 1, 2, 3 |  |
| Win - OIB - TP - Health Monitoring - D - Endpoint Analytics - v3.4 | Device configuration | Device | Devices | Test, 1, 2, 3 |  |

## Skipped by default

These are created and assigned only when named with `-PolicyName`.

| Policy | Reason |
| --- | --- |
| Win - OIB - ES - Attack Surface Reduction - D - ASR Rules (L2) - v3.7 | Sets the same rules as ASR Rules (Audit Mode). Deploy it after auditing, in place of the audit policy. |
| Win - OIB - ES - Encryption - U - Personal Data Encryption - v3.4 | Conflicts with Automatic Restart Sign-On and needs Windows Enterprise. |
