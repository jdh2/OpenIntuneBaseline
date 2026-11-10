# Deploying the baseline with update rings

[`Deploy-OpenIntuneBaseline.ps1`](../Deploy-OpenIntuneBaseline.ps1) imports the **Windows** and **Windows 365** baselines into Intune. It creates update ring groups for each policy category and assigns the policies to those groups ring by ring, with assignment filters to keep policies off devices that don't support them.

Everything the script does is driven by [`DeploymentConfig.json`](DeploymentConfig.json), so you can change categories, rings, filters and exclusions without editing the script.

For the full list of groups, and which ring groups and filters each policy is assigned to, see [MAPPING.md](MAPPING.md), or [MAPPING-Hybrid.md](MAPPING-Hybrid.md) for hybrid environments.

## Gnosis overlay

By default the script deploys the baseline with the **Gnosis** customisations applied on top. The upstream `WINDOWS` and `WINDOWS365` folders are never changed, so they can still be updated straight from [upstream](https://github.com/SkipToTheEndpoint/OpenIntuneBaseline). The customisations live in the [`GNOSIS`](../GNOSIS) folder and under `overlays.Gnosis` in [DeploymentConfig.json](DeploymentConfig.json):

| Change | Policy | Why |
| --- | --- | --- |
| Replaced | `Win - OIB - ES - Windows LAPS - D - LAPS Configuration - v4.0` | The managed local admin account is named `Gnosis` instead of the default `WLapsAdmin` |
| Replaced | `Win - OIB - ES - Local Group Membership - D - Local Administrators - v3.7` | Restricts the Administrators group to the `Gnosis` account, to match LAPS. Upstream's version names `WLapsAdmin`, which would remove the Gnosis LAPS account from Administrators |
| Left out | The three `Win - OIB - WUfB - Ring …` update rings and three `Win - OIB - WUfB Drivers - Ring …` driver profiles | Windows updates are managed by ConnectWise RMM, not Intune |

A default run therefore deploys 72 policies instead of 78. Deploy the upstream baseline unchanged with `-Overlay None`:

```powershell
.\Deploy-OpenIntuneBaseline.ps1 -TenantId contoso.onmicrosoft.com -Overlay None
```

How the overlay works:

- **Replacing a policy:** a file in `GNOSIS\Windows` replaces the upstream policy with the same `OIBID:` tag in its description, or failing that, the same name. It keeps the upstream policy's name, so the result looks like any other OIB policy in Intune.
- **Leaving policies out:** upstream policies whose names match a pattern in `overlays.Gnosis.exclude` aren't loaded at all, even with `-PolicyName`.
- **Keeping in step with upstream:** if upstream releases a new version of a replaced policy (a new name or version number), or removes it, the script stops and names the overlay file to update, so an old Gnosis copy is never deployed in place of a newer upstream policy. To update it, copy upstream's new file into `GNOSIS\Windows` and re-apply the one-line change.
- **Existing policies:** like everything else, a policy that already exists in the tenant under the same name is reused, not changed. A tenant that already has upstream's LAPS or Local Administrators policy under those names keeps them as they are.
- **Encoding:** keep the overlay files in a path without `IntuneManagement` in it. The repo's `.gitattributes` treats every `IntuneManagement` folder (other than `WINDOWS` and `BYOD`) as UTF-16, which would garble UTF-8 exports.

To add another customer's overlay, add an entry under `overlays` with its folder and exclude list, and run with `-Overlay <name>`, or set `defaultOverlay`.

## Hybrid and on-premises AD environments

The baseline is written for cloud-native, Entra-joined devices. Some of its settings break devices that are hybrid-joined or still depend on on-premises Active Directory. Run the script with `-Environment Hybrid` to deploy the baseline without them:

```powershell
.\Deploy-OpenIntuneBaseline.ps1 -TenantId contoso.onmicrosoft.com -Environment Hybrid
```

The settings are removed from each policy before it is created in Intune. The baseline files on disk are not changed, so pulling new baseline versions from upstream still works. Policies that lost settings get ` - Hybrid` added to their names, and a note in their description.

| Policy | Settings removed | Why |
| --- | --- | --- |
| Network Security – Disable NTLM | Restrict incoming NTLM, restrict outgoing NTLM, LAN Manager authentication level | Breaks shares, printers and apps reached by IP address or without a Kerberos SPN, and NTLMv1 devices. **Nothing is left, so the policy is not deployed.** |
| Device Security – Security Hardening | Minimum SMB version (client and server) | A minimum of SMB 3.1.1 blocks Server 2012 R2 and older, including domain controllers' SYSVOL and NETLOGON |
| Device Security – Local Security Policies | LAN Manager authentication level, SMB signing required (client and server), restrict remote SAM calls | Breaks NTLMv1 devices, SMB servers without signing, and remote inventory tools |
| Local Group Membership – Local Administrators | The group membership setting | Replaces the local Administrators group, removing Domain Admins. **Nothing is left, so the policy is not deployed.** |
| Device Security – User Rights | Access this computer from the network, deny network logon, deny RDP logon | Cuts domain users and local-account admin tools off from the device |
| Device Security – Device Guard, Credential Guard and HVCI | Credential Guard, LSA protection | Both are set with UEFI lock; Credential Guard breaks PEAP-MSCHAPv2 Wi-Fi and VPN, NTLMv1 and unconstrained delegation |

Points to be aware of:

- **Removing a setting doesn't turn the feature off.** It returns it to the Windows default or to your Group Policy. In particular, Windows 11 22H2 and later turns on Credential Guard by default (without UEFI lock) on eligible Enterprise and Education devices, and Windows 11 24H2 requires SMB signing by default. If you rely on PEAP-MSCHAPv2 or servers without signing, set those explicitly in Group Policy or move to EAP-TLS and signing-capable servers.
- **SMBv1 stays off and insecure guest logons stay blocked** in hybrid mode. Those match the Windows 11 defaults and rarely affect domain resources.
- **Windows LAPS is not changed.** It still backs up to Entra ID; decide how it should coexist with any AD-based LAPS before rolling it out.
- **The list is in the configuration.** Edit `hybrid.removeSettings` in [DeploymentConfig.json](DeploymentConfig.json) to add or remove settings. Each entry names a policy pattern and the exact setting IDs; if a baseline update renames or drops one of those settings, the script stops and tells you which, rather than silently deploying it.
- **Hybrid and cloud-native policies have different names**, so a tenant that already has the cloud-native versions gets the hybrid versions created alongside them. Unassign or delete whichever set you don't want.

## What it creates

| Object | Count | Notes |
| --- | --- | --- |
| Assignment filters | 2 | `OIB - Windows - Windows 365 Cloud PCs` and `OIB - Windows - Virtual Machines` |
| Security groups | 64 by default: 4 per category and audience | `<Category> - Update Ring - <Test, 1, 2 or 3> - <Users or Devices>`. Only the audiences a category's policies target get groups (see [Ring membership](#ring-membership)) |
| Policies | 72 by default (78 with `-Overlay None`) | Settings catalog, endpoint security, compliance, health monitoring, plus update rings and driver updates with `-Overlay None` (see [Gnosis overlay](#gnosis-overlay)) |
| Assignments | 1 per policy per ring | Only for the rings named with `-Ring` |

### Categories

Each category gets its own four ring groups, so you can roll out Office changes without waiting on Defender changes, and so on.

| Category | Policies |
| --- | --- |
| Microsoft Office | `* - Microsoft Office - *` |
| Microsoft Edge | `* - Microsoft Edge - *` |
| Microsoft OneDrive | `* - Microsoft OneDrive - *` |
| Microsoft Defender | Attack Surface Reduction, Defender Antivirus, Defender Antivirus Updates rings |
| Encryption | BitLocker, Personal Data Encryption |
| Identity and Access | Windows Hello for Business, Cloud Kerberos Trust, Passwordless, LAPS, Local Administrators, Microsoft Accounts |
| Windows Security | Device Security, Network Security, Windows Firewall, Internet Explorer (Legacy), Windows Update rings, driver update rings, Delivery Optimisation, Reports and Telemetry |
| Windows Experience | Windows User Experience, In-Box App Removal, Microsoft Store, Endpoint Analytics |
| Device Compliance | All Windows compliance policies |
| Windows 365 | The Windows 365 baseline |

### Ring membership

Each category has separate ring groups for users and devices, and each policy goes to one of them based on its scope:

| Audience | Policies | Group name |
| --- | --- | --- |
| Users | User-scoped policies (`- U -`), which includes every compliance policy | `<Category> - Update Ring - <Ring> - Users` |
| Devices | Everything else: device-scoped policies (`- D -`), update rings, driver updates and Defender update rings | `<Category> - Update Ring - <Ring> - Devices` |

A category only gets the groups for the audiences it uses. Device Compliance, for example, only has Users groups and Windows Security only has Devices groups.

By default every ring group is static: you choose which users and devices go in each ring. Two switches make rings 1 to 3 dynamic instead, so they fill themselves. The Test groups always stay static.

| Switch | Groups | Ring 1 | Ring 2 | Ring 3 |
| --- | --- | --- | --- | --- |
| `-DynamicDeviceRings` | `- Devices` | Device ID starts `0`–`4` (about 31%) | `5`–`9` (about 31%) | `a`–`f` (about 38%) |
| `-DynamicUserRings` | `- Users` | Object ID starts `0`–`4` (about 31%) | `5`–`9` (about 31%) | `a`–`f` (about 38%) |

The device rules only include Windows devices managed by Intune (`deviceOSType` Windows, `managementType` MDM). The user rules only include enabled member accounts, so guests and disabled accounts are left out; service and shared accounts are included. Every eligible device or user lands in exactly one of rings 1 to 3. The full rules are under each audience's `dynamicRules` in [DeploymentConfig.json](DeploymentConfig.json).

```powershell
.\Deploy-OpenIntuneBaseline.ps1 -TenantId contoso.onmicrosoft.com -DynamicDeviceRings -DynamicUserRings
```

Points to be aware of:

- **Dynamic groups need Microsoft Entra ID P1** (included in Microsoft 365 E3, E5 and Business Premium).
- **Assigning a dynamic ring reaches everyone in it straight away.** Assigning ring 3 with both switches effectively finishes the rollout.
- **Every category's group for a ring has the same members**, but categories still roll out independently, because a category only reaches a ring once you run the script with that ring and category.
- **Test members are also in one of rings 1 to 3.** That's fine: they get each policy from whichever group is assigned first.
- **New groups take time to fill.** Entra ID processes new dynamic rules in the background, which can take from minutes to several hours in large tenants.

**Switching existing groups.** The script decides static or dynamic per run, from the switches. Groups that already exist are left as they are, and the script reports any that don't match. Add `-UpdateGroupRules` to bring them in line:

- **Static to dynamic, or a changed rule:** the rule is applied. The script refuses to convert a static group that has members, because converting removes them.
- **Dynamic to static:** running with `-UpdateGroupRules` but without the switch converts the groups back to static, keeping their current members as ordinary members.

```powershell
.\Deploy-OpenIntuneBaseline.ps1 -TenantId contoso.onmicrosoft.com -SkipAssignments -DynamicDeviceRings -UpdateGroupRules
```

  ```powershell
  .\Deploy-OpenIntuneBaseline.ps1 -TenantId contoso.onmicrosoft.com -SkipAssignments -UpdateGroupRules
  ```

### Small tenants

For a small client, say 10 users, separate update rings are usually more work than they're worth. Run the script with `-TestRingOnly`:

```powershell
.\Deploy-OpenIntuneBaseline.ps1 -TenantId contoso.onmicrosoft.com -TestRingOnly
```

It creates only the Test groups (16 by default: one per category and audience) and assigns every policy to them. Put the client's users and devices in those groups, and the whole baseline applies to them. You can try it out on one or two devices first by adding only those, then add the rest.

- The baseline's own Production update policies (Windows Update, driver and Defender updates) are assigned to the Test groups. Pilot and UAT stay unassigned, as usual.
- `-Ring` can only be `Test`, and `-DynamicDeviceRings` and `-DynamicUserRings` have no effect, because the Test groups are always static.
- If the tenant later grows, run the script without `-TestRingOnly` to add the ring 1 to 3 groups. The existing Test groups and assignments are kept.

### Ring-specific policies

The baseline already ships three-ring sets for Windows Update, driver updates and Defender Antivirus updates. The Gnosis overlay leaves out the Windows Update and driver sets, so by default only the Defender Antivirus updates set is deployed. Only the Production policy of each set is assigned, to every ring group. The Pilot and UAT policies are created but left unassigned, so you can use them later if you want faster update rings:

| Baseline policy | Ring groups |
| --- | --- |
| `Ring 1 - Pilot` | Not assigned |
| `Ring 2 - UAT` | Not assigned |
| `Ring 3 - Production` | Test, 1, 2, 3 |

So every ring gets the same Production update settings, and the update ring groups only control *when* each user or device starts receiving them. If you later assign Pilot or UAT to a ring, remove Production from that ring first, because a device can't get two update ring policies without them conflicting.

### Filters

| Policy | Filter | Why |
| --- | --- | --- |
| Windows 365 baseline (all 3 policies) | Include *Windows 365 Cloud PCs* | Cloud PC settings only belong on Cloud PCs |
| BitLocker (OS Disk) | Exclude *Virtual Machines* | BitLocker isn't supported on Cloud PCs or AVD |
| Compliance: Device Health - BitLocker, Code Integrity, SecureBoot | Exclude *Virtual Machines* | Cloud PCs use the Windows 365 Device Health compliance policy instead, as the [Windows 365 README](../WINDOWS365/README.md) recommends |

The *Virtual Machines* filter matches a model starting with `Cloud PC` or `VMware`, a model containing `Virtual` (Hyper-V, Azure/AVD, Parallels, VirtualBox), or the Windows Enterprise multi-session SKU. Check the models in your tenant (**Devices > Windows**, *Model* column) and adjust the rule in the configuration if you use another hypervisor. If a filter already exists with the same name, the script keeps its rule and tells you when it differs.

With `-Overlay None`, note that driver update profiles don't support assignment filters, so the driver rings also reach any Cloud PCs or VMs in the `Windows Security` ring groups. If you don't want that, keep virtual devices (or their users) out of those groups.

### Skipped by default

| Policy | Reason |
| --- | --- |
| ASR Rules (L2) | Sets the same 19 rules as ASR Rules (Audit Mode). Deploy audit mode first, review the results in Defender, then replace it with L2 |
| Personal Data Encryption | Conflicts with Automatic Restart Sign-On (per the baseline manifest) and needs Windows Enterprise |

Include either one with `-PolicyName`. The script refuses to deploy both halves of a conflicting pair in one run. It can't see what's already in your tenant, though, so remove the other policy's assignment yourself before you assign the replacement.

## Prerequisites

- PowerShell 7 or later. Windows PowerShell 5.1 isn't supported
- The `Microsoft.Graph.Authentication` module: `Install-Module Microsoft.Graph.Authentication -Scope CurrentUser`
- An account that can consent to `Group.ReadWrite.All` and `DeviceManagementConfiguration.ReadWrite.All` (Intune Administrator plus Groups Administrator, or Global Administrator)
- The licences listed in the [Windows](../WINDOWS/README.md) and [Windows 365](../WINDOWS365/README.md) READMEs. Several policies need Windows Enterprise, and some need Defender for Endpoint

## Rolling out

**1. Preview.** This connects read-only and lists what would be created and assigned:

```powershell
.\Deploy-OpenIntuneBaseline.ps1 -TenantId contoso.onmicrosoft.com -WhatIf
```

**2. Deploy to the Test ring.** This creates the filters, all the ring groups and the policies, then assigns every policy to its category's Test group:

```powershell
.\Deploy-OpenIntuneBaseline.ps1 -TenantId contoso.onmicrosoft.com
```

**3. Add members.** Put your test devices in the `... - Update Ring - Test - Devices` groups and your test users in the `... - Update Ring - Test - Users` groups. Nothing applies until a group has members. Fill the ring 1 to 3 groups the same way as you widen the rollout, or let them fill themselves with `-DynamicDeviceRings` and `-DynamicUserRings`.

**4. Widen the rollout.** Once a ring is stable, run the script again with more rings. It adds only the missing assignments and leaves existing ones alone:

```powershell
.\Deploy-OpenIntuneBaseline.ps1 -TenantId contoso.onmicrosoft.com -Ring Test,1
```

You can widen one category at a time:

```powershell
.\Deploy-OpenIntuneBaseline.ps1 -TenantId contoso.onmicrosoft.com -Ring Test,1,2 -Category 'Microsoft Edge','Microsoft OneDrive'
```

### Other options

| Parameter | Use |
| --- | --- |
| `-Platform Windows` | Deploy only one baseline (`Windows` or `Windows365`) |
| `-PolicyName '*BitLocker*'` | Deploy only matching policies (wildcards). Also includes policies skipped by default |
| `-Environment Hybrid` | Remove the settings that break on-premises AD (see above). Default is `CloudNative` |
| `-Overlay None` | Deploy the upstream baseline without the Gnosis customisations (see [Gnosis overlay](#gnosis-overlay)). Default is `Gnosis` |
| `-SkipAssignments` | Create everything but assign nothing |
| `-TestRingOnly` | For small tenants: create only the Test groups and assign every policy to them (see [Small tenants](#small-tenants)) |
| `-DynamicDeviceRings` | Create the ring 1 to 3 Devices groups as dynamic groups (see [Ring membership](#ring-membership)) |
| `-DynamicUserRings` | Create the ring 1 to 3 Users groups as dynamic groups |
| `-UpdateGroupRules` | Bring existing ring groups in line with this run's static or dynamic choice: convert between static and dynamic, and update rules that differ |
| `-ExportMapping .\Deployment\MAPPING.md` | Regenerate the mapping document from the configuration, without connecting to Graph. Run it after changing the configuration or pulling a new baseline version |
| `-Force` | Skip the confirmation prompt |
| `-Verbose` | Show the JSON sent for each object |

## Safe to run again

- Filters, groups and policies are matched by display name. Existing ones are reused and never changed, except ring groups when you pass `-UpdateGroupRules`.
- A policy's settings are never updated. When the baseline publishes a new version, its name changes (for example `v4.0` to `v4.1`), so the new version is created alongside the old one. Move your rings across, then delete the old policy.
- Assignments are only ever added. Intune's assign call replaces all of a policy's assignments, so the script reads the current ones and sends them back with the new rings. Assignments you added by hand, including exclusions, are kept.
- If the name of an existing group, filter or policy matches more than one object, that item fails rather than the script guessing.

## Why separate user and device groups?

Device-scoped policies (`- D -` in the name) apply most reliably to device groups, because they don't wait for a user to sign in, and Microsoft recommends device groups for update rings in particular. User-scoped policies (`- U -`) and compliance policies are designed for user groups. Keeping the two apart means each policy reaches people or machines through one path only, so a ring means the same thing for every policy in it. Filters work with both.

Put only devices in the `- Devices` groups and only users in the `- Users` groups. A user added to a device group isn't targeted by its policies, and a device added to a user group isn't either.
