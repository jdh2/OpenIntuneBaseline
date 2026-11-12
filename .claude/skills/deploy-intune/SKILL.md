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
  If it has parameters not covered below, ask about them too, unless this skill says never to
  use them.
- `Deployment/DeploymentConfig.json`: `rings` (ring names), `categories` (names and the
  policy names each matches), `audiences` (which rings have dynamic rules), `overlays` and
  `defaultOverlay`.

## 3. Ask the questions

Use AskUserQuestion: at most 4 questions per call, 2 to 4 options each, and recommended
options first. The person can always type their own answer. Ask in these rounds:

**Round 1**
- **Tenant**, which also sets the mode. The question box can only take typed text through
  the app's own **Other** choice, which can't be renamed, so say so in the question:
  "Which tenant should the baseline be deployed to? Choose **Other** and type its
  `*.onmicrosoft.com` domain or tenant ID." Give exactly these two options, with no
  placeholder option for the tenant:
  - **Cancel**: stop; nothing is run.
  - **Export mapping only**: no tenant needed; writes the mapping document without signing
    in and changes nothing (`-ExportMapping`).

  A typed tenant means Deploy (a preview always runs first). Remember exactly what they
  typed: they will have to type it again before deploying. If Other is chosen with nothing
  typed, treat it as Cancel. If the text isn't a domain or a tenant ID (a GUID), say so and
  ask this question again.
- **Platform**: Windows and Windows 365 (default) / Windows only (`-Platform Windows`). There
  is no Windows 365-only option.
- **Environment**: Cloud native (default) / Hybrid or on-prem AD (`-Environment Hybrid`).

**Round 2**
- **Ring setup**: Normal rings (default) / Test ring only, for small tenants (`-TestRingOnly`)
  / Create everything but assign nothing (`-SkipAssignments`).
- **Dynamic groups** (multiSelect, skip with test ring only): none, all static (default) /
  Dynamic device rings / Dynamic user rings. Mention that dynamic groups need Entra ID P1,
  and that policies are never assigned to dynamic groups by this skill (see below).
- **Overlay**: the default overlay from the config (say which) / each other overlay /
  None (upstream baseline only).
- **Update policies**: Leave out as the overlay says (default) / Include
  (`-IncludeUpdatePolicies`, for tenants where ConnectWise RMM doesn't manage updates).
  Skip this when the overlay is None.

**Round 3**
- **Rings** (multiSelect; skip with test ring only or assign nothing): the rings from the
  config that can be assigned (see below). Default is the first ring (Test). Explain that
  rollout is gradual and rings are added on later runs. If only one ring can be assigned,
  offer it and "Don't assign anything" (`-SkipAssignments`).
- **Which policies**: All policies (default) / Choose categories / Only policies matching
  names (they type wildcard patterns for `-PolicyName`).

**Round 4** (only if they chose categories)
- List every category from the config's `categories` as options, so the person picks rather
  than types. Leave out `Windows 365` (and any other category that only matches `Win365`
  policies) when the platform is Windows only.
- Split them into multiSelect questions of 2 to 4 categories each, in as few
  AskUserQuestion calls as possible (up to 4 questions, so 16 categories, per call). Label
  them "Categories (1 of 3)" and so on, and say they can pick none from a list.
- They must pick at least one category in total. Pass the picks as `-Category`.

For export mapping only, still ask the platform, environment, ring setup, overlay and update
policy questions (they change the mapping), skip the dynamic groups, rings and policies
questions, and ask for an output path (default `.\MAPPING-<date>.md`). Run it, report where
the file is, and stop there.

### Dynamic groups are never assigned

Dynamic groups fill with users or devices automatically, so assigning a policy to one rolls
it out straight away. The team decides when settings go out, so this skill never assigns
policies to dynamic groups. Static groups are fine, because new ones are created empty.

- A ring can't be assigned if any audience chosen as dynamic has a dynamic rule for that
  ring in the config (`audiences[].dynamicRules`). With dynamic device or user rings, that
  normally leaves only the Test ring. The script assigns a ring to both audiences at once,
  so a ring is blocked even if only one of its audiences is dynamic.
- Don't offer blocked rings, and refuse them if the person types them, explaining why. They
  can assign those policies themselves in Intune when they are ready.

### Existing groups are never changed

Never pass `-UpdateGroupRules`, and don't offer to change existing groups. If a ring group
already exists, the script reuses it as it is and reports any difference from the
configuration (for example, a group that is dynamic but configured as static). Pass those
reports on; don't offer to fix them.

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
- Before each run, tell the person a Microsoft sign-in window may open and, if it does, to
  sign in with their own account for that tenant. If they already signed in recently, the
  cached sign-in is used and no window appears; that's fine, because the `Target tenant:`
  and `Account:` lines show who it signed in as.

If the sign-in window should appear and doesn't, or sign-in fails (for example, Conditional Access or a
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

Check the preview's group results for every ring that would be assigned. If any of those
groups already exists in the tenant as a dynamic group (the script reports it as "dynamic
but configured as static"), deploying would assign policies to it. Stop, name the groups,
and offer to start again without those rings. Deploy nothing.

If the preview fails or shows problems, stop and help sort them out. Deploy nothing.

## 6. Confirm the tenant

Show the tenant ID and account from the preview and say plainly that the next step changes
this tenant. Then ask the person, with AskUserQuestion, to **type the tenant name again**
to deploy: "To deploy, choose **Other** and type the tenant name again, exactly as you
entered it at the start." Give exactly these two options, with no placeholder option for
the tenant:
- **Cancel**: deploy nothing.
- **Change options**: deploy nothing and go back to the questions (step 3).

If Other is chosen with nothing typed, treat it as Cancel.

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
- It signs in again, this time with write permissions, so the person may see a second
  sign-in window. Check that its `Target tenant:` ID is the same as the preview's. If it isn't, stop the run straight away and tell them.

## 8. Report

Summarise the results the script prints: what was created, reused, assigned, skipped and
failed, with any failures listed in full and what they mean (for example, a 403 on driver
profiles means the Windows data connector hasn't been confirmed in Intune). Remind them that
wider rings are added by running again with more rings once the current ones prove stable.
