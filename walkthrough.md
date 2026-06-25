# Nextgeeker Annihilator - Build Walkthrough

## What was built

[NextgeekerAnnihilator.ps1](file:///c:/Users/samke/OneDrive/Documents/Nextgeeker-Annihilator/NextgeekerAnnihilator.ps1)
is a 1,065-line, 46KB native PowerShell 5.1 eradication utility built for Windows 11.
It requires no compiled binaries, works within Application Control policy, and
self-elevates via UAC when run as a standard user.

---

## Architecture Overview

```
NextgeekerAnnihilator.ps1
 |
 +-- Phase 1: SCAN (read-only, no changes)
 |    +-- Invoke-RegistryScan       -> HKLM/HKCU policy hives, ExtensionInstallForcelist
 |    +-- Invoke-GroupPolicyScan    -> System32\GroupPolicy, GroupPolicyUsers
 |    +-- Invoke-ExtensionScan      -> Orphaned/policy-forced Chromium extensions
 |    +-- Invoke-TaskScan           -> Behavioral anomaly scan of all Task Scheduler XML
 |    +-- Invoke-ScriptPayloadScan  -> Known payload scripts in System32
 |    +-- Invoke-FirefoxPolicyScan  -> Firefox distribution/policies.json
 |    +-- Invoke-ShortcutScan       -> .LNK files on Desktop, Start Menu, Taskbar
 |
 +-- Phase 2: REPORT
 |    +-- Write-FullReport          -> Color-coded 7-category console report
 |
 +-- Phase 3: CONFIRM
 |    +-- Interactive y/N prompt (skipped with -Force)
 |
 +-- Phase 4: ERADICATE (with prior backup)
      +-- Stop-BrowserProcesses        [1/8] Kill chrome, msedge, firefox, brave, wscript
      +-- Invoke-FullBackup            [2/8] reg.exe export + file copy + Restore Point
      +-- Remove-RegistryPolicies      [3/8] Delete all 9 policy hive trees
      +-- Remove-GroupPolicies         [4/8] Delete GP folders + gpupdate /force
      +-- Remove-ScheduledTasks        [5/8] schtasks.exe /Delete + fallback file delete
      +-- Remove-PayloadScripts        [6/8] Delete System32 payloads + Firefox policies
      +-- Remove-AnomalousExtensions   [7/8] Purge extension directories from disk
      +-- Repair-HijackedShortcuts     [8/8] Strip URL arguments from .LNK files
```

---

## How to Run

### Scan Mode (recommended first run — no changes made)
```powershell
# Right-click PowerShell -> Run as Administrator, then:
powershell -ExecutionPolicy Bypass -File ".\NextgeekerAnnihilator.ps1" -ScanOnly
```

### Interactive Removal Mode (backs up everything before deleting)
```powershell
powershell -ExecutionPolicy Bypass -File ".\NextgeekerAnnihilator.ps1"
# -> Review the report, then type 'y' to confirm eradication
```

### Fully Automated Removal (CI / scripted deployment)
```powershell
powershell -ExecutionPolicy Bypass -File ".\NextgeekerAnnihilator.ps1" -Force
```

### Backup Only (creates restore point and registry exports, no deletion)
```powershell
powershell -ExecutionPolicy Bypass -File ".\NextgeekerAnnihilator.ps1" -BackupOnly
```

---

## What Gets Backed Up

Before any deletion, the script creates `C:\NextgeekerBackup_YYYYMMDD_HHMMSS\` containing:

| Backup Target | Method |
|---|---|
| All 9 browser policy registry hives | `reg.exe export` -> `.reg` files |
| PowerShell ExecutionPolicy key | `reg.exe export` |
| System32\GroupPolicy directory | `Copy-Item -Recurse` |
| System32\GroupPolicyUsers directory | `Copy-Item -Recurse` |
| Each script payload file | `Copy-Item` |
| Each Firefox policies.json | `Copy-Item` |
| Each anomalous extension folder | `Copy-Item -Recurse` |
| Windows System Restore Point | `Checkpoint-Computer` |

---

## Threat Vectors Covered (from research document)

| Threat | Indicator | Action |
|---|---|---|
| Registry forced extensions | `ExtensionInstallForcelist` in Chrome/Edge/Firefox/Brave hives | Delete entire policy tree |
| Group Policy lock-in | System32\GroupPolicy + GroupPolicyUsers dirs | Delete + gpupdate /force |
| Scheduled task persistence | `Updater_PrivacyBlocker_PR1`, `NvOptimizerTaskUpdater_V2` | schtasks /Delete |
| Script payloads | `NvWinSearchOptimizer.ps1` + 3 others in System32 | Delete + backup |
| Firefox policy override | `distribution\policies.json` | Delete |
| Shortcut hijacking | URL args in browser .LNK files | Strip URL, resave shortcut |
| Orphaned extensions | Extensions present on disk but not in browser Preferences | Purge directory |
| Execution policy abuse | HKLM ExecutionPolicy = Unrestricted/Bypass | Reset to Restricted |

---

## Validation Results

| Check | Result |
|---|---|
| PowerShell AST parse (`ParseInput`) | **PASS - Zero errors** |
| Self-elevation trigger (non-admin) | **PASS - Correctly requests UAC** |
| Script line count | **1,065 lines** |
| File size | **46,379 bytes** |
| Encoding | **ASCII-safe (no Unicode box chars)** |

---

## Post-Removal Steps (Manual)

After running the tool, you MUST complete all three of these:

1. **Browser Cloud Sync Isolation** — Disconnect browser sync accounts to prevent
   the hijacker config from re-downloading from the cloud.
   - Chrome: Profile icon > Sync is on > Turn Off > Delete Data
   - Edge: `edge://settings/profiles/sync` > Turn off sync
   - Firefox: Settings > Account > Disconnect profile sync

2. **Hard Browser Profile Reset**
   - Chrome: Settings > Reset settings > Restore to original defaults
   - Edge: Settings > Reset settings > Restore to default values
   - Firefox: `about:support` > Refresh Firefox

3. **Installed Apps Audit** — Settings > Apps > Installed apps > Sort by Install date.
   Remove any unrecognised program installed near the date of the hijacking.
