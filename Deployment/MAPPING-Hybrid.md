# Update ring group and assignment mapping (Hybrid)

Generated from [`DeploymentConfig.json`](DeploymentConfig.json) and the Windows and Windows365 baseline files by `Deploy-OpenIntuneBaseline.ps1 -ExportMapping`, for the **Hybrid** environment. Regenerate it after changing the configuration or updating the baseline:

```powershell
.\Deploy-OpenIntuneBaseline.ps1 -ExportMapping .\Deployment\MAPPING-Hybrid.md -Environment Hybrid
```

A default run deploys **76 policies** into **10 categories**, creating **40 groups** and **2 filters**. Policies are only assigned to the rings named with `-Ring` in each run, so this is the full plan once every ring is rolled out.

## Groups

| Category | Policies | Ring Test group | Ring 1 group | Ring 2 group | Ring 3 group |
| --- | --- | --- | --- | --- | --- |
| [Windows 365](#windows-365) | 3 | `Windows 365 - Update Ring - Test` | `Windows 365 - Update Ring - 1` | `Windows 365 - Update Ring - 2` | `Windows 365 - Update Ring - 3` |
| [Device Compliance](#device-compliance) | 9 | `Device Compliance - Update Ring - Test` | `Device Compliance - Update Ring - 1` | `Device Compliance - Update Ring - 2` | `Device Compliance - Update Ring - 3` |
| [Microsoft Office](#microsoft-office) | 4 | `Microsoft Office - Update Ring - Test` | `Microsoft Office - Update Ring - 1` | `Microsoft Office - Update Ring - 2` | `Microsoft Office - Update Ring - 3` |
| [Microsoft Edge](#microsoft-edge) | 7 | `Microsoft Edge - Update Ring - Test` | `Microsoft Edge - Update Ring - 1` | `Microsoft Edge - Update Ring - 2` | `Microsoft Edge - Update Ring - 3` |
| [Microsoft OneDrive](#microsoft-onedrive) | 2 | `Microsoft OneDrive - Update Ring - Test` | `Microsoft OneDrive - Update Ring - 1` | `Microsoft OneDrive - Update Ring - 2` | `Microsoft OneDrive - Update Ring - 3` |
| [Microsoft Defender](#microsoft-defender) | 7 | `Microsoft Defender - Update Ring - Test` | `Microsoft Defender - Update Ring - 1` | `Microsoft Defender - Update Ring - 2` | `Microsoft Defender - Update Ring - 3` |
| [Encryption](#encryption) | 1 | `Encryption - Update Ring - Test` | `Encryption - Update Ring - 1` | `Encryption - Update Ring - 2` | `Encryption - Update Ring - 3` |
| [Identity and Access](#identity-and-access) | 5 | `Identity and Access - Update Ring - Test` | `Identity and Access - Update Ring - 1` | `Identity and Access - Update Ring - 2` | `Identity and Access - Update Ring - 3` |
| [Windows Security](#windows-security) | 30 | `Windows Security - Update Ring - Test` | `Windows Security - Update Ring - 1` | `Windows Security - Update Ring - 2` | `Windows Security - Update Ring - 3` |
| [Windows Experience](#windows-experience) | 8 | `Windows Experience - Update Ring - Test` | `Windows Experience - Update Ring - 1` | `Windows Experience - Update Ring - 2` | `Windows Experience - Update Ring - 3` |

## Filters

| Filter | Rule | Applied to |
| --- | --- | --- |
| `OIB - Windows - Windows 365 Cloud PCs` | `(device.model -startsWith "Cloud PC")` | include: Win365 - OIB - Compliance - U - Device Health - v1.0<br>include: Win365 - OIB - Device Security - D - Connectivity Settings - v1.0<br>include: Win365 - OIB - Device Security - D - Resource Redirection - v1.0 |
| `OIB - Windows - Virtual Machines` | `(device.model -startsWith "Cloud PC") or (device.model -contains "Virtual") or (device.model -startsWith "VMware") or (device.operatingSystemSKU -eq "ServerRdsh")` | exclude: Win - OIB - CP - Device Health - U - BitLocker - v4.0<br>exclude: Win - OIB - CP - Device Health - U - Code Integrity - v4.0<br>exclude: Win - OIB - CP - Device Health - U - SecureBoot - v4.0<br>exclude: Win - OIB - ES - Encryption - D - BitLocker (OS Disk) - v3.7 |

## Hybrid changes

These settings are removed before the policies are created, because they break on-premises Active Directory. Changed policies get `Hybrid` added to their names. The baseline files themselves are not changed. Edit `hybrid.removeSettings` in the configuration to change the list.

| Policy | Removed settings | Why |
| --- | --- | --- |
| Win - OIB - ES - Local Group Membership - D - Local Administrators - v3.7 - Hybrid | `localusersandgroups_configure` | Replaces the local Administrators group, removing Domain Admins and groups added by Group Policy.<br>**Not deployed: no settings left.** |
| Win - OIB - SC - Device Security - D - Local Security Policies - v4.0 - Hybrid | `localpoliciessecurityoptions_microsoftnetworkclient_digitallysigncommunicationsalways`<br>`localpoliciessecurityoptions_microsoftnetworkserver_digitallysigncommunicationsalways`<br>`localpoliciessecurityoptions_networkaccess_restrictclientsallowedtomakeremotecallstosam`<br>`localpoliciessecurityoptions_networksecurity_lanmanagerauthenticationlevel` | NTLMv2-only, required SMB signing and restricted remote SAM calls break older SMB servers, NTLMv1 devices and remote inventory tools. |
| Win - OIB - SC - Device Security - D - Security Hardening - v4.0 - Hybrid | `lanmanserver_minsmb2dialect`<br>`lanmanworkstation_minsmb2dialect` | A minimum SMB version of 3.1.1 blocks file servers and domain controllers on Windows Server 2012 R2 or older, including SYSVOL and NETLOGON. |
| Win - OIB - SC - Device Security - D - User Rights - v3.7 - Hybrid | `userrights_accessfromnetwork`<br>`userrights_denyaccessfromnetwork`<br>`userrights_denyremotedesktopserviceslogon` | Limits network access to Administrators and blocks local accounts from network and RDP logon, cutting off domain users and remote admin tools. |
| Win - OIB - SC - Device Security - U - Device Guard, Credential Guard and HVCI - v3.7 - Hybrid | `deviceguard_lsacfgflags`<br>`localsecurityauthority_configurelsaprotectedprocess` | Credential Guard and LSA protection with UEFI lock break PEAP-MSCHAPv2 Wi-Fi and VPN, NTLMv1, unconstrained delegation and third-party LSA plugins, and are hard to undo. |
| Win - OIB - SC - Network Security - D - Disable NTLM - v3.8 - Hybrid | `localpoliciessecurityoptions_networksecurity_lanmanagerauthenticationlevel`<br>`localpoliciessecurityoptions_networksecurity_restrictntlm_incomingntlmtraffic`<br>`localpoliciessecurityoptions_networksecurity_restrictntlm_outgoingntlmtraffictoremoteservers` | Blocking NTLM breaks shares, printers and apps reached by IP address or without a Kerberos SPN, and NTLMv1-only devices.<br>**Not deployed: no settings left.** |

## Policies by category

**Rings** lists the ring groups a policy is assigned to once those rings are rolled out. Policies marked *Not assigned* are created but left unassigned, as set in `ringSpecificPolicies`.

### Windows 365

Groups: `Windows 365 - Update Ring - Test`, `Windows 365 - Update Ring - 1`, `Windows 365 - Update Ring - 2`, `Windows 365 - Update Ring - 3`

| Policy | Type | Scope | Rings | Filter |
| --- | --- | --- | --- | --- |
| Win365 - OIB - Compliance - U - Device Health - v1.0 | Compliance | User | Test, 1, 2, 3 | include `OIB - Windows - Windows 365 Cloud PCs` |
| Win365 - OIB - Device Security - D - Connectivity Settings - v1.0 | Settings catalog | Device | Test, 1, 2, 3 | include `OIB - Windows - Windows 365 Cloud PCs` |
| Win365 - OIB - Device Security - D - Resource Redirection - v1.0 | Settings catalog | Device | Test, 1, 2, 3 | include `OIB - Windows - Windows 365 Cloud PCs` |

### Device Compliance

Groups: `Device Compliance - Update Ring - Test`, `Device Compliance - Update Ring - 1`, `Device Compliance - Update Ring - 2`, `Device Compliance - Update Ring - 3`

| Policy | Type | Scope | Rings | Filter |
| --- | --- | --- | --- | --- |
| Win - OIB - CP - Defender - U - Real-Time Protection - v4.0 | Compliance | User | Test, 1, 2, 3 |  |
| Win - OIB - CP - Defender - U - Security Intelligence - v4.0 | Compliance | User | Test, 1, 2, 3 |  |
| Win - OIB - CP - Device Health - U - BitLocker - v4.0 | Compliance | User | Test, 1, 2, 3 | exclude `OIB - Windows - Virtual Machines` |
| Win - OIB - CP - Device Health - U - Code Integrity - v4.0 | Compliance | User | Test, 1, 2, 3 | exclude `OIB - Windows - Virtual Machines` |
| Win - OIB - CP - Device Health - U - SecureBoot - v4.0 | Compliance | User | Test, 1, 2, 3 | exclude `OIB - Windows - Virtual Machines` |
| Win - OIB - CP - Device Security - U - Antispyware - v4.0 | Compliance | User | Test, 1, 2, 3 |  |
| Win - OIB - CP - Device Security - U - Antivirus - v4.0 | Compliance | User | Test, 1, 2, 3 |  |
| Win - OIB - CP - Device Security - U - Firewall - v4.0 | Compliance | User | Test, 1, 2, 3 |  |
| Win - OIB - CP - Device Security - U - TPM - v4.0 | Compliance | User | Test, 1, 2, 3 |  |

### Microsoft Office

Groups: `Microsoft Office - Update Ring - Test`, `Microsoft Office - Update Ring - 1`, `Microsoft Office - Update Ring - 2`, `Microsoft Office - Update Ring - 3`

| Policy | Type | Scope | Rings | Filter |
| --- | --- | --- | --- | --- |
| Win - OIB - SC - Microsoft Office - D - Security - v3.6 | Settings catalog | Device | Test, 1, 2, 3 |  |
| Win - OIB - SC - Microsoft Office - D - Updates - v3.0 | Settings catalog | Device | Test, 1, 2, 3 |  |
| Win - OIB - SC - Microsoft Office - U - Config and Experience - v3.6 | Settings catalog | User | Test, 1, 2, 3 |  |
| Win - OIB - SC - Microsoft Office - U - Security - v4.0 | Settings catalog | User | Test, 1, 2, 3 |  |

### Microsoft Edge

Groups: `Microsoft Edge - Update Ring - Test`, `Microsoft Edge - Update Ring - 1`, `Microsoft Edge - Update Ring - 2`, `Microsoft Edge - Update Ring - 3`

| Policy | Type | Scope | Rings | Filter |
| --- | --- | --- | --- | --- |
| Win - OIB - SC - Microsoft Edge - D - Security - v4.0 | Settings catalog | Device | Test, 1, 2, 3 |  |
| Win - OIB - SC - Microsoft Edge - D - Updates - v4.0 | Settings catalog | Device | Test, 1, 2, 3 |  |
| Win - OIB - SC - Microsoft Edge - U - Extensions - v3.1 | Settings catalog | User | Test, 1, 2, 3 |  |
| Win - OIB - SC - Microsoft Edge - U - Management - v4.0 | Settings catalog | User | Test, 1, 2, 3 |  |
| Win - OIB - SC - Microsoft Edge - U - Password Management - v3.0 | Settings catalog | User | Test, 1, 2, 3 |  |
| Win - OIB - SC - Microsoft Edge - U - Profiles, Sign-In and Sync - v4.0 | Settings catalog | User | Test, 1, 2, 3 |  |
| Win - OIB - SC - Microsoft Edge - U - User Experience - v4.0 | Settings catalog | User | Test, 1, 2, 3 |  |

### Microsoft OneDrive

Groups: `Microsoft OneDrive - Update Ring - Test`, `Microsoft OneDrive - Update Ring - 1`, `Microsoft OneDrive - Update Ring - 2`, `Microsoft OneDrive - Update Ring - 3`

| Policy | Type | Scope | Rings | Filter |
| --- | --- | --- | --- | --- |
| Win - OIB - SC - Microsoft OneDrive - D - Configuration - v3.2 | Settings catalog | Device | Test, 1, 2, 3 |  |
| Win - OIB - SC - Microsoft OneDrive - U - Configuration - v3.8 | Settings catalog | User | Test, 1, 2, 3 |  |

### Microsoft Defender

Groups: `Microsoft Defender - Update Ring - Test`, `Microsoft Defender - Update Ring - 1`, `Microsoft Defender - Update Ring - 2`, `Microsoft Defender - Update Ring - 3`

| Policy | Type | Scope | Rings | Filter |
| --- | --- | --- | --- | --- |
| Win - OIB - ES - Attack Surface Reduction - D - ASR Rules (Audit Mode) - v3.1 | Endpoint security | Device | Test, 1, 2, 3 |  |
| ~~Win - OIB - ES - Attack Surface Reduction - D - ASR Rules (L2) - v3.7~~ *(skipped by default)* | Endpoint security | Device | Test, 1, 2, 3 |  |
| Win - OIB - ES - Defender Antivirus - D - AV Configuration - v4.0 | Endpoint security | Device | Test, 1, 2, 3 |  |
| Win - OIB - ES - Defender Antivirus - D - Security Experience - v4.0 | Endpoint security | Device | Test, 1, 2, 3 |  |
| Win - OIB - ES - Defender Antivirus Updates - Ring 1 - Pilot - v3.4 | Endpoint security | Device | *Not assigned* |  |
| Win - OIB - ES - Defender Antivirus Updates - Ring 2 - UAT - v3.4 | Endpoint security | Device | *Not assigned* |  |
| Win - OIB - ES - Defender Antivirus Updates - Ring 3 - Production - v3.4 | Endpoint security | Device | Test, 1, 2, 3 |  |
| Win - OIB - SC - Defender Antivirus - D - Additional Configuration - v4.0 | Settings catalog | Device | Test, 1, 2, 3 |  |

### Encryption

Groups: `Encryption - Update Ring - Test`, `Encryption - Update Ring - 1`, `Encryption - Update Ring - 2`, `Encryption - Update Ring - 3`

| Policy | Type | Scope | Rings | Filter |
| --- | --- | --- | --- | --- |
| Win - OIB - ES - Encryption - D - BitLocker (OS Disk) - v3.7 | Endpoint security | Device | Test, 1, 2, 3 | exclude `OIB - Windows - Virtual Machines` |
| ~~Win - OIB - ES - Encryption - U - Personal Data Encryption - v3.4~~ *(skipped by default)* | Endpoint security | User | Test, 1, 2, 3 |  |

### Identity and Access

Groups: `Identity and Access - Update Ring - Test`, `Identity and Access - Update Ring - 1`, `Identity and Access - Update Ring - 2`, `Identity and Access - Update Ring - 3`

| Policy | Type | Scope | Rings | Filter |
| --- | --- | --- | --- | --- |
| ~~Win - OIB - ES - Local Group Membership - D - Local Administrators - v3.7 - Hybrid~~ *(not deployed in hybrid: all settings removed)* | Endpoint security | Device | Test, 1, 2, 3 |  |
| Win - OIB - ES - Windows Hello for Business - D - WHfB Configuration - v3.2 | Endpoint security | Device | Test, 1, 2, 3 |  |
| Win - OIB - ES - Windows LAPS - D - LAPS Configuration - v4.0 | Endpoint security | Device | Test, 1, 2, 3 |  |
| Win - OIB - SC - Credential Management - D - Passwordless - v3.3 | Settings catalog | Device | Test, 1, 2, 3 |  |
| Win - OIB - SC - Microsoft Accounts - D - Configuration - v3.2 | Settings catalog | Device | Test, 1, 2, 3 |  |
| Win - OIB - SC - Windows Hello for Business - D - Cloud Kerberos Trust - v3.5 | Settings catalog | Device | Test, 1, 2, 3 |  |

### Windows Security

Groups: `Windows Security - Update Ring - Test`, `Windows Security - Update Ring - 1`, `Windows Security - Update Ring - 2`, `Windows Security - Update Ring - 3`

| Policy | Type | Scope | Rings | Filter |
| --- | --- | --- | --- | --- |
| Win - OIB - ES - Windows Firewall - D - Firewall Configuration - v3.1 | Endpoint security | Device | Test, 1, 2, 3 |  |
| Win - OIB - ES - Windows Firewall - D - Security Rules - v3.8 | Endpoint security | Device | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - D - Administrator Protection - v4.0.1 | Settings catalog | Device | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - D - Audit and Event Logging - v4.0 | Settings catalog | Device | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - D - Config Refresh - v3.2 | Settings catalog | Device | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - D - Enhanced Phishing Protection - v3.0 | Settings catalog | Device | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - D - Local Security Policies - v4.0 - Hybrid | Settings catalog | Device | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - D - Location and Privacy - v3.2 | Settings catalog | Device | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - D - Login and Lock Screen - v3.8 | Settings catalog | Device | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - D - Printing - v3.7 | Settings catalog | Device | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - D - Remote Desktop Services and RPC - v3.0 | Settings catalog | Device | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - D - Script File Associations - v4.0 | Settings catalog | Device | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - D - Security Hardening - v4.0 - Hybrid | Settings catalog | Device | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - D - Timezone - v3.4 | Settings catalog | Device | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - D - User Rights - v3.7 - Hybrid | Settings catalog | Device | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - D - Windows Package Manager - v3.5 | Settings catalog | Device | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - D - Windows Subsystem for Linux - v3.2 | Settings catalog | Device | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - U - Device Guard, Credential Guard and HVCI - v3.7 - Hybrid | Settings catalog | User | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - U - Power and Device Lock - v4.0 | Settings catalog | User | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - U - Windows Sandbox - v3.4 | Settings catalog | User | Test, 1, 2, 3 |  |
| Win - OIB - SC - Device Security - U - Windows Spotlight and Org Messages - v3.0 | Settings catalog | User | Test, 1, 2, 3 |  |
| Win - OIB - SC - Internet Explorer (Legacy) - D - Security - v4.0 | Settings catalog | Device | Test, 1, 2, 3 |  |
| ~~Win - OIB - SC - Network Security - D - Disable NTLM - v3.8 - Hybrid~~ *(not deployed in hybrid: all settings removed)* | Settings catalog | Device | Test, 1, 2, 3 |  |
| Win - OIB - SC - Windows Update for Business - D - Delivery Optimisation - v3.0 | Settings catalog | Device | Test, 1, 2, 3 |  |
| Win - OIB - SC - Windows Update for Business - D - Reports and Telemetry - v3.0 | Settings catalog | Device | Test, 1, 2, 3 |  |
| Win - OIB - WUfB - Ring 1 - Pilot - v3.0 | Update ring | Device | *Not assigned* |  |
| Win - OIB - WUfB - Ring 2 - UAT - v3.0 | Update ring | Device | *Not assigned* |  |
| Win - OIB - WUfB - Ring 3 - Production - v3.0 | Update ring | Device | Test, 1, 2, 3 |  |
| Win - OIB - WUfB Drivers - Ring 1 - Pilot - v3.0 | Driver updates | Device | *Not assigned* |  |
| Win - OIB - WUfB Drivers - Ring 2 - UAT - v3.0 | Driver updates | Device | *Not assigned* |  |
| Win - OIB - WUfB Drivers - Ring 3 - Production - v3.0 | Driver updates | Device | Test, 1, 2, 3 |  |

### Windows Experience

Groups: `Windows Experience - Update Ring - Test`, `Windows Experience - Update Ring - 1`, `Windows Experience - Update Ring - 2`, `Windows Experience - Update Ring - 3`

| Policy | Type | Scope | Rings | Filter |
| --- | --- | --- | --- | --- |
| Win - OIB - SC - Microsoft Store - D - Configuration - v3.8 | Settings catalog | Device | Test, 1, 2, 3 |  |
| Win - OIB - SC - Microsoft Store - U - Configuration - v3.3 | Settings catalog | User | Test, 1, 2, 3 |  |
| Win - OIB - SC - Windows Apps - D - In-Box App Removal - v4.0 | Settings catalog | Device | Test, 1, 2, 3 |  |
| Win - OIB - SC - Windows User Experience - D - Automatic Restart Sign-On - v3.8 | Settings catalog | Device | Test, 1, 2, 3 |  |
| Win - OIB - SC - Windows User Experience - D - Feature Configuration - v4.0 | Settings catalog | Device | Test, 1, 2, 3 |  |
| Win - OIB - SC - Windows User Experience - D - Settings Sync - v3.7 | Settings catalog | Device | Test, 1, 2, 3 |  |
| Win - OIB - SC - Windows User Experience - U - Copilot - v3.8 | Settings catalog | User | Test, 1, 2, 3 |  |
| Win - OIB - TP - Health Monitoring - D - Endpoint Analytics - v3.4 | Device configuration | Device | Test, 1, 2, 3 |  |

## Skipped by default

These are created and assigned only when named with `-PolicyName`.

| Policy | Reason |
| --- | --- |
| Win - OIB - ES - Attack Surface Reduction - D - ASR Rules (L2) - v3.7 | Sets the same rules as ASR Rules (Audit Mode). Deploy it after auditing, in place of the audit policy. |
| Win - OIB - ES - Encryption - U - Personal Data Encryption - v3.4 | Conflicts with Automatic Restart Sign-On and needs Windows Enterprise. |
