---
name: deploy-intune
description: Guided deployment of the OpenIntuneBaseline policies to a customer's Intune tenant with Deploy-OpenIntuneBaseline.ps1. Use when the user wants to deploy, preview, roll out to more rings, or export the mapping for the Intune baseline.
---

# Deploy the OpenIntuneBaseline to a tenant

Walk the person through the options of `Deploy-OpenIntuneBaseline.ps1` with multiple-choice
questions, always preview the changes first, and deploy only after the person types the
tenant name again to confirm it. The script changes a customer's tenant, so these steps are
never skipped.

## 1. Check the environment first

Stop with a clear message if any of these fail:

- **Local Windows session.** The script signs in interactively as the person running it
  (device code sign-in is blocked), so it must run on their own Windows machine, in a local
  session of the Claude desktop app's Code tab. If this is a cloud session or not Windows,
  say so and stop.
- **Up to date.** Run `git pull` in the repo root. If it fails or there are local changes,
  tell the person and ask whether to continue.
- **PowerShell 7 and the Graph module.** Check with
  `pwsh -NoProfile -Command "Get-Module -ListAvailable Microsoft.Graph.Authentication | Select-Object -First 1 Version"`.
  If `pwsh` is missing, tell them to install PowerShell 7. If the module is missing, offer to run
  `Install-Module Microsoft.Graph.Authentication -Scope CurrentUser`.

## 2. Read the current options

Don't rely on lists written here. Read them fresh each time:

- The `param()` block and comment-based help at the top of `Deploy-OpenIntuneBaseline.ps1`.
  If it has parameters not covered below, ask about them too.
- `Deployment/DeploymentConfig.json`: `rings` (ring names), `categories` (category names),
  `overlays` and `defaultOverlay`.

## 3. Ask the questions

Use AskUserQuestion: at most 4 questions per call, 2 to 4 options each, and recommended
options first. The person can always type their own answer. Ask in these rounds:

**Round 1**
- **Tenant** (free text): the tenant's `*.onmicrosoft.com` domain or tenant ID. Always
  required. Offer one placeholder option such as "Type the tenant domain" and expect a typed
  answer. Remember exactly what they typed: they will have to type it again before deploying.
- **Mode**: Deploy (a preview always runs first) / Export mapping only (`-ExportMapping`, no
  sign-in, changes nothing).
- **Platform**: Windows and Windows 365 (default) / Windows only / Windows 365 only.
- **Environment**: Cloud native (default) / Hybrid or on-prem AD (`-Environment Hybrid`).

**Round 2**
- **Rings** (multiSelect): the rings from the config. Default is the first ring (Test).
  Explain that rollout is gradual and rings are added on later runs. Skip this question if
  they choose test ring only below.
- **Ring setup**: Normal rings (default) / Test ring only, for small tenants (`-TestRingOnly`)
  / Create everything but assign nothing (`-SkipAssignments`).
- **Overlay**: the default overlay from the config (say which) / each other overlay /
  None (upstream baseline only).
- **Update policies**: Leave out as the overlay says (default) / Include
  (`-IncludeUpdatePolicies`, for tenants where ConnectWise RMM doesn't manage updates).
  Skip this when the overlay is None.

**Round 3** (only ask what applies)
- **Scope**: All policies (default) / Only some categories (they type names from the config)
  / Only policies matching names (they type wildcard patterns for `-PolicyName`).
- **Dynamic groups** (multiSelect, skip with test ring only): none (default, all static) /
  Dynamic device rings / Dynamic user rings. Mention that dynamic groups need Entra ID P1.
- **Existing groups**: Leave as they are (default) / Convert to match this run
  (`-UpdateGroupRules`). Explain that a static group with members is never made dynamic.

For export mapping only, the tenant isn't needed; ask for an output path instead (default
`.\MAPPING-<tenant or date>.md`), run it, report where the file is, and stop there.

Validate typed category names against the config and ask again if one doesn't match.

## 4. Confirm the options

Show the person:
- the exact command, with each value quoted for PowerShell, and
- a one-line plain summary, for example: "contoso.onmicrosoft.com: Windows and Windows 365,
  cloud native, Gnosis overlay, assign ring Test."

Say that a read-only preview runs first, then ask yes/no with AskUserQuestion. Run nothing
until they say yes.

## How to run the script (preview and deployment)

- Build the command as
  `pwsh -NoProfile -File .\Deploy-OpenIntuneBaseline.ps1 -TenantId '<tenant>' <options>`.
- Run everything, sign-in included, in **one** `pwsh` process: the sign-in doesn't carry over
  to a later command.
- Run it in the background and check the output as it goes, because a full deployment can
  take longer than a single command's time limit.
- Before each run, tell the person a Microsoft sign-in window is about to open and to sign in
  with their own account for that tenant.

If the sign-in window doesn't appear or sign-in fails (for example, Conditional Access or a
window that can't open from this session), stop the run. Give the person the preview command
and then the deployment command **without** `-Force`, to paste in that order into their own
PowerShell 7 window from the repo folder. The script's own prompt then asks them to confirm
the tenant before it changes anything.

## 5. Preview (always)

The preview is mandatory and can't be skipped. If the person asks to skip it, explain that
every deployment is previewed first and carry on.

Run the confirmed command with `-WhatIf` added (and no `-Force`). It signs in with read-only
permissions and changes nothing. From its output, note the `Target tenant:` ID and the
`Account:` it signed in with, then summarise what *would* be created, reused, assigned and
skipped, and any errors or warnings it reports.

If the preview fails or shows problems, stop and help sort them out. Deploy nothing.

## 6. Confirm the tenant

Show the tenant ID and account from the preview and say plainly that the next step changes
this tenant. Then ask the person, with AskUserQuestion, to **type the tenant name again**
to deploy, with "Cancel" as the other option.

- Compare what they type with the tenant they entered in round 1, ignoring case and spaces
  at the ends. It must match exactly; a partial or similar name does not count.
- If it doesn't match, or they cancel, deploy nothing. Say what they entered both times and
  offer to start again from the questions.
- Never fill the tenant in for them or offer it as a ready-made option.

## 7. Deploy

Only after the tenant matches:

- Run exactly the previewed command, without `-WhatIf` and with `-Force` added. The script's
  own confirmation prompt can't be answered from here, and the person has confirmed by typing
  the tenant. Never add `-Force` in any other case.
- If the person wants to change any option at this point, go back to step 4: the changed
  command needs its own preview and tenant confirmation.
- It signs in again (the person may see a second sign-in window), this time with write permissions. Check that its `Target tenant:` ID is
  the same as the preview's. If it isn't, stop the run straight away and tell them.

## 8. Report

Summarise the results the script prints: what was created, reused, assigned, skipped and
failed, with any failures listed in full and what they mean (for example, a 403 on driver
profiles means the Windows data connector hasn't been confirmed in Intune). Remind them that
wider rings are added by running again with more rings once the current ones prove stable.
