---
name: deploy-intune
description: Guided deployment of the OpenIntuneBaseline policies to a customer's Intune tenant with Deploy-OpenIntuneBaseline.ps1. Use when the user wants to deploy, preview, roll out to more rings, or export the mapping for the Intune baseline.
---

# Deploy the OpenIntuneBaseline to a tenant

Walk the person through the options of `Deploy-OpenIntuneBaseline.ps1` with multiple-choice
questions, show them the exact command, and run it only after they confirm. The script changes
a customer's tenant, so never run it without that confirmation.

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
- **Tenant** (free text): the tenant ID or `*.onmicrosoft.com` domain. Always required, so the
  run can't land in the wrong tenant. Offer one placeholder option such as "Type the tenant
  domain" and expect a typed answer.
- **Mode**: Preview (`-WhatIf`, read-only, recommended first) / Deploy / Export mapping only
  (`-ExportMapping`, no sign-in).
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
`.\MAPPING-<tenant or date>.md`).

Validate typed category names against the config and ask again if one doesn't match.

## 4. Confirm

Show the person:
- the exact command, with each value quoted for PowerShell, and
- a one-line plain summary, for example: "Preview in contoso.onmicrosoft.com: Windows and
  Windows 365, cloud native, Gnosis overlay, assign ring Test."

For a real deployment (not Preview or export), suggest a Preview first if they haven't run
one for this tenant in this session. Then ask a final yes/no with AskUserQuestion. Run nothing
until they say yes.

## 5. Run it

- Build the command as
  `pwsh -NoProfile -File .\Deploy-OpenIntuneBaseline.ps1 -TenantId '<tenant>' <options>`.
- For a real deployment, add `-Force`. The script's own confirmation prompt can't be answered
  from here, and the person has already confirmed in step 4. Never add `-Force` without that.
- Run everything, sign-in included, in **one** `pwsh` process: the sign-in doesn't carry over
  to a later command.
- Run it in the background and check the output as it goes, because a full deployment can
  take longer than a single command's time limit.
- Tell the person a Microsoft sign-in window is about to open, and to sign in with their own
  account for that tenant. Check that the script's `Target tenant:` line matches the tenant
  they gave. If it doesn't, stop the run straight away and tell them.

If the sign-in window doesn't appear or sign-in fails (for example, Conditional Access or a
window that can't open from this session), stop the run. Give the person the same command
without `-Force` to paste into their own PowerShell 7 window, from the repo folder, so they
can run and confirm it there.

## 6. Report

Summarise the results the script prints: what was created, reused, assigned, skipped and
failed, with any failures listed in full and what they mean (for example, a 403 on driver
profiles means the Windows data connector hasn't been confirmed in Intune). For a Preview,
summarise what *would* change and offer to run the real deployment with the same options.
After a successful deployment, remind them that wider rings are added by running again with
more rings once the current ones prove stable.
