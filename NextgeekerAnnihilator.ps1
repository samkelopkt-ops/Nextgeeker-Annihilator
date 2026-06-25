#Requires -Version 5.1
<#
.SYNOPSIS
    Nextgeeker Annihilator - Windows 11 Elite Browser Hijacker Eradication Utility

.DESCRIPTION
    Behavioral anomaly scanner and remover for the Nextgeeker browser hijacker and its
    persistence vectors: registry policy abuse, group policy locks, rogue scheduled tasks,
    PowerShell payload scripts, forced browser extensions, and shortcut hijacking.

    Scan Mode:    Read-only audit; no modifications made.
    Removal Mode: Backs up, then eradicates all flagged vectors with user confirmation.

.PARAMETER ScanOnly
    Perform a read-only scan and print the report. Do not prompt for removal.

.PARAMETER Force
    Skip the user confirmation prompt and proceed directly to removal after scanning.

.PARAMETER BackupOnly
    Export registry keys and copy policy files to a local backup folder only; no removal.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\NextgeekerAnnihilator.ps1 -ScanOnly
    powershell -ExecutionPolicy Bypass -File .\NextgeekerAnnihilator.ps1
    powershell -ExecutionPolicy Bypass -File .\NextgeekerAnnihilator.ps1 -BackupOnly
#>

[CmdletBinding()]
param(
    [switch]$ScanOnly,
    [switch]$Force,
    [switch]$BackupOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ============================================================
# CONSTANTS
# ============================================================

$script:BackupRoot = 'C:\'
$script:BackupDir  = ''

$script:KnownMaliciousScripts = @(
    'NvWinSearchOptimizer.ps1',
    'Printworkflowservice.ps1',
    'Windowsupdater1.ps1',
    'Optimizerwindows.ps1'
)

$script:KnownMaliciousTasks = @(
    'Updater_PrivacyBlocker_PR1',
    'MicrosoftWindowsOptimizerUpdateTask_PR1',
    'NvOptimizerTaskUpdater_V2'
)

$script:BrowserExecutables   = @('chrome.exe', 'msedge.exe', 'firefox.exe', 'brave.exe')
$script:BrowserProcessNames  = @('chrome', 'msedge', 'firefox', 'brave', 'wscript', 'cscript')

$script:PolicyHiveMap = @(
    @{ Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Google\Chrome' }
    @{ Hive = 'HKCU'; Path = 'SOFTWARE\Policies\Google\Chrome' }
    @{ Hive = 'HKLM'; Path = 'SOFTWARE\WOW6432Node\Policies\Google\Chrome' }
    @{ Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Edge' }
    @{ Hive = 'HKCU'; Path = 'SOFTWARE\Policies\Microsoft\Edge' }
    @{ Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Mozilla\Firefox' }
    @{ Hive = 'HKCU'; Path = 'SOFTWARE\Policies\Mozilla\Firefox' }
    @{ Hive = 'HKLM'; Path = 'SOFTWARE\Policies\BraveSoftware\Brave' }
    @{ Hive = 'HKCU'; Path = 'SOFTWARE\Policies\BraveSoftware\Brave' }
)

$script:ChromiumProfiles = @(
    @{ Browser = 'Google Chrome'; LocalPath = 'Google\Chrome\User Data' }
    @{ Browser = 'Microsoft Edge'; LocalPath = 'Microsoft\Edge\User Data' }
    @{ Browser = 'Brave Browser';  LocalPath = 'BraveSoftware\Brave-Browser\User Data' }
)

# ============================================================
# TERMINAL OUTPUT HELPERS
# ============================================================

function Write-Banner {
    Clear-Host
    $now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $adminLabel = if (Test-IsAdmin) { 'YES  [Administrator]' } else { 'NO   [Standard User - elevation required]' }
    Write-Host '+--------------------------------------------------------+' -ForegroundColor Cyan
    Write-Host '|       N E X T G E E K E R   A N N I H I L A T O R    |' -ForegroundColor Cyan
    Write-Host '|            Windows 11 Elite Malware Remover             |' -ForegroundColor Cyan
    Write-Host '+--------------------------------------------------------+' -ForegroundColor Cyan
    Write-Host "  Timestamp : $now" -ForegroundColor White
    Write-Host "  Elevated  : $adminLabel" -ForegroundColor White
    Write-Host ''
}

function Write-Log {
    param(
        [ValidateSet('Info','Success','Warn','Error','Section')]
        [string]$Level,
        [string]$Message
    )
    switch ($Level) {
        'Info'    { Write-Host "  [.] $Message" -ForegroundColor Gray   }
        'Success' { Write-Host "  [+] $Message" -ForegroundColor Green  }
        'Warn'    { Write-Host "  [!] $Message" -ForegroundColor Yellow }
        'Error'   { Write-Host "  [X] $Message" -ForegroundColor Red    }
        'Section' {
            Write-Host ''
            Write-Host "  == $Message ==" -ForegroundColor Magenta
        }
    }
}

function Write-SectionHeader {
    param([string]$Title)
    Write-Host ''
    Write-Host "  ----------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "  ----------------------------------------------------------" -ForegroundColor DarkGray
}

# ============================================================
# PRIVILEGE HELPERS
# ============================================================

function Test-IsAdmin {
    $id        = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-SelfElevate {
    Write-Log -Level Warn -Message 'Requesting elevation via UAC...'
    $argList = @('-ExecutionPolicy', 'Bypass', '-NoProfile', '-File', "`"$PSCommandPath`"")
    if ($ScanOnly)   { $argList += '-ScanOnly'   }
    if ($Force)      { $argList += '-Force'      }
    if ($BackupOnly) { $argList += '-BackupOnly' }
    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs
    } catch {
        Write-Log -Level Error -Message 'UAC elevation rejected. Run PowerShell As Administrator manually.'
    }
    exit 0
}

# ============================================================
# REGISTRY POLICY SCANNER
# ============================================================

function Invoke-RegistryScan {
    param([ref]$Findings, [ref]$ForcedExtIds)

    foreach ($entry in $script:PolicyHiveMap) {
        $psPath = if ($entry.Hive -eq 'HKLM') { "HKLM:\$($entry.Path)" } else { "HKCU:\$($entry.Path)" }
        if (-not (Test-Path -LiteralPath $psPath)) { continue }

        $Findings.Value += [PSCustomObject]@{
            Category    = 'RegistryPolicy'
            Hive        = $entry.Hive
            KeyPath     = $entry.Path
            ValueName   = '(Key Exists)'
            ValueData   = '(Policy node present on consumer machine)'
            Description = 'Browser policy tree forces managed configuration on non-managed device.'
        }

        $flPath = "$psPath\ExtensionInstallForcelist"
        if (Test-Path -LiteralPath $flPath) {
            $props = Get-Item -LiteralPath $flPath |
                     Select-Object -ExpandProperty Property -ErrorAction SilentlyContinue
            foreach ($propName in $props) {
                if ($propName -match '^(PSPath|PSParentPath|PSChildName|PSProvider|PSDrive)') { continue }
                $valData = (Get-ItemProperty -LiteralPath $flPath -Name $propName -ErrorAction SilentlyContinue).$propName
                if ($null -eq $valData) { continue }
                $valStr  = $valData.ToString()

                $Findings.Value += [PSCustomObject]@{
                    Category    = 'ForcelistEntry'
                    Hive        = $entry.Hive
                    KeyPath     = "$($entry.Path)\ExtensionInstallForcelist"
                    ValueName   = $propName
                    ValueData   = $valStr
                    Description = 'Force-installed extension prevents manual removal in the browser UI.'
                }

                $rawId = if ($valStr -like '*;*') { ($valStr -split ';')[0].Trim() } else { $valStr.Trim() }
                if ($rawId.Length -eq 32) { $ForcedExtIds.Value += $rawId }
            }
        }
    }

    $pwshKey = 'HKLM:\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell'
    if (Test-Path -LiteralPath $pwshKey) {
        $currentPolicy = (Get-ItemProperty -LiteralPath $pwshKey `
                          -Name 'ExecutionPolicy' -ErrorAction SilentlyContinue).ExecutionPolicy
        if ($currentPolicy -in @('Unrestricted','Bypass')) {
            $Findings.Value += [PSCustomObject]@{
                Category    = 'ExecutionPolicy'
                Hive        = 'HKLM'
                KeyPath     = 'SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell'
                ValueName   = 'ExecutionPolicy'
                ValueData   = $currentPolicy
                Description = 'Execution policy weakened from Restricted to permit arbitrary script execution.'
            }
        }
    }
}

# ============================================================
# GROUP POLICY FOLDER SCANNER
# ============================================================

function Invoke-GroupPolicyScan {
    param([ref]$Findings)
    $sys32 = [Environment]::GetFolderPath('System')
    foreach ($gpName in @('GroupPolicy', 'GroupPolicyUsers')) {
        $gpPath = Join-Path $sys32 $gpName
        if (Test-Path -LiteralPath $gpPath) {
            $Findings.Value += [PSCustomObject]@{
                Category    = 'GroupPolicy'
                FolderPath  = $gpPath
                Description = 'Local Group Policy template directory locks browser startup parameters.'
            }
        }
    }
}

# ============================================================
# EXTENSION ANOMALY SCANNER
# ============================================================

function Get-ManifestInfo {
    param([string]$ExtensionIdFolder)
    $defaults = @{ Name = '(unknown)'; Version = '(unknown)'; UpdateUrl = '(unknown)' }
    try {
        $versionDir = Get-ChildItem -LiteralPath $ExtensionIdFolder -Directory -ErrorAction SilentlyContinue |
                      Sort-Object Name -Descending | Select-Object -First 1
        if (-not $versionDir) { return $defaults }

        $manifestPath = Join-Path $versionDir.FullName 'manifest.json'
        if (-not (Test-Path -LiteralPath $manifestPath)) { return $defaults }

        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue |
                    ConvertFrom-Json -ErrorAction SilentlyContinue
        if (-not $manifest) { return $defaults }

        return @{
            Name      = if ($manifest.name)       { $manifest.name }       else { '(unknown)' }
            Version   = if ($manifest.version)    { $manifest.version }    else { '(unknown)' }
            UpdateUrl = if ($manifest.update_url) { $manifest.update_url } else { '(none)' }
        }
    } catch { return $defaults }
}

function Invoke-ExtensionScan {
    param([array]$ForcedExtIds, [ref]$Findings)

    $localAppData = [Environment]::GetFolderPath('LocalApplicationData')

    foreach ($browserDef in $script:ChromiumProfiles) {
        $userDataPath = Join-Path $localAppData $browserDef.LocalPath
        if (-not (Test-Path -LiteralPath $userDataPath)) { continue }

        $profileDirs = Get-ChildItem -LiteralPath $userDataPath -Directory -ErrorAction SilentlyContinue
        foreach ($profileDir in $profileDirs) {
            $extensionsDir = Join-Path $profileDir.FullName 'Extensions'
            if (-not (Test-Path -LiteralPath $extensionsDir)) { continue }

            $registeredSet = @{}
            $prefPath = Join-Path $profileDir.FullName 'Preferences'
            if (Test-Path -LiteralPath $prefPath) {
                try {
                    $pref = Get-Content -LiteralPath $prefPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue |
                            ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($pref -and $pref.extensions -and $pref.extensions.settings) {
                        $pref.extensions.settings.PSObject.Properties.Name |
                            ForEach-Object { $registeredSet[$_] = $true }
                    }
                } catch {}
            }

            $extFolders = Get-ChildItem -LiteralPath $extensionsDir -Directory -ErrorAction SilentlyContinue |
                          Where-Object { $_.Name.Length -eq 32 }

            foreach ($extDir in $extFolders) {
                $extId          = $extDir.Name
                $isPolicyForced = $ForcedExtIds -contains $extId
                $isOrphaned     = -not $registeredSet.ContainsKey($extId)

                if (-not ($isPolicyForced -or $isOrphaned)) { continue }

                $meta = Get-ManifestInfo -ExtensionIdFolder $extDir.FullName
                $tags = [System.Collections.Generic.List[string]]::new()
                if ($isPolicyForced) { $tags.Add('Registry-Forced') }
                if ($isOrphaned)     { $tags.Add('Orphaned (not in profile settings)') }

                $Findings.Value += [PSCustomObject]@{
                    Category    = 'Extension'
                    Browser     = $browserDef.Browser
                    Profile     = $profileDir.Name
                    ExtensionId = $extId
                    ExtName     = $meta.Name
                    Version     = $meta.Version
                    UpdateUrl   = $meta.UpdateUrl
                    FolderPath  = $extDir.FullName
                    Tags        = ($tags -join ', ')
                }
            }
        }
    }
}

# ============================================================
# SCHEDULED TASK SCANNER
# ============================================================

function Get-ScriptPathsFromXml {
    param([string]$XmlContent)
    $found            = [System.Collections.Generic.List[string]]::new()
    $scriptExtensions = @('.ps1','.vbs','.js','.bat','.cmd')
    $xmlCleaned       = $XmlContent -replace '&quot;','' `
                                    -replace '"','' `
                                    -replace "'",'' `
                                    -replace [regex]'<[^>]+>',''

    $pos = 0
    while (($pos = $xmlCleaned.IndexOf('C:\', $pos, [StringComparison]::OrdinalIgnoreCase)) -ge 0) {
        $bestEnd = -1
        foreach ($ext in $scriptExtensions) {
            $extPos = $xmlCleaned.IndexOf($ext, $pos, [StringComparison]::OrdinalIgnoreCase)
            if ($extPos -gt $pos -and $extPos -lt ($pos + 300)) {
                $candidate = $extPos + $ext.Length
                if ($bestEnd -lt 0 -or $candidate -lt $bestEnd) { $bestEnd = $candidate }
            }
        }

        if ($bestEnd -gt 0) {
            $rawSegment = $xmlCleaned.Substring($pos, $bestEnd - $pos).Trim()
            try {
                $expanded = [Environment]::ExpandEnvironmentVariables($rawSegment)
                $resolved = [IO.Path]::GetFullPath($expanded)
                if ((Test-Path -LiteralPath $resolved -PathType Leaf) -and ($found -notcontains $resolved)) {
                    $found.Add($resolved)
                }
            } catch {}
            $pos = $bestEnd
        } else {
            $pos += 3
        }
    }
    return $found.ToArray()
}

function Invoke-TaskScan {
    param([ref]$TaskFindings, [ref]$ScriptFindings)

    $sys32     = [Environment]::GetFolderPath('System')
    $tasksRoot = Join-Path $sys32 'Tasks'
    if (-not (Test-Path -LiteralPath $tasksRoot)) { return }

    $taskFiles = Get-ChildItem -LiteralPath $tasksRoot -File -Recurse -ErrorAction SilentlyContinue
    foreach ($taskFile in $taskFiles) {
        try {
            $taskName   = $taskFile.FullName.Substring($tasksRoot.Length).TrimStart('\')
            $xmlContent = Get-Content -LiteralPath $taskFile.FullName -Raw -ErrorAction SilentlyContinue
            if ([string]::IsNullOrEmpty($xmlContent)) { continue }

            $suspicious = $false
            $reason     = ''

            if ($script:KnownMaliciousTasks -contains $taskFile.Name) {
                $suspicious = $true
                $reason     = "Matches known browser hijacker task name: $($taskFile.Name)"
            }

            if (-not $suspicious -and $xmlContent -like '*<Command>*') {
                $hasInterpreter = ($xmlContent -like '*powershell.exe*') -or
                                  ($xmlContent -like '*wscript.exe*')    -or
                                  ($xmlContent -like '*cscript.exe*')    -or
                                  ($xmlContent -like '*cmd.exe*')

                $hasScriptMarker = ($xmlContent -like '*.ps1*')              -or
                                   ($xmlContent -like '*.vbs*')              -or
                                   ($xmlContent -like '*-EncodedCommand*')   -or
                                   ($xmlContent -like '*Invoke-WebRequest*') -or
                                   ($xmlContent -like '*DownloadString*')    -or
                                   ($xmlContent -like '*Net.WebClient*')

                if ($hasInterpreter -and $hasScriptMarker) {
                    $suspicious = $true
                    $reason     = 'Behavioral anomaly - scripting interpreter executing payload via Task Scheduler.'
                }
            }

            if (-not $suspicious) { continue }

            $TaskFindings.Value += [PSCustomObject]@{
                Category = 'ScheduledTask'
                TaskName = $taskName
                FilePath = $taskFile.FullName
                Reason   = $reason
            }

            $extractedPaths = Get-ScriptPathsFromXml -XmlContent $xmlContent
            foreach ($ep in $extractedPaths) {
                $alreadyAdded = $ScriptFindings.Value | Where-Object { $_.FilePath -eq $ep }
                if (-not $alreadyAdded) {
                    $ScriptFindings.Value += [PSCustomObject]@{
                        Category    = 'PayloadScript'
                        FilePath    = $ep
                        Description = "Payload script referenced by malicious task: $taskName"
                    }
                }
            }
        } catch {}
    }
}

# ============================================================
# SYSTEM32 SCRIPT PAYLOAD SCANNER
# ============================================================

function Invoke-ScriptPayloadScan {
    param([ref]$ScriptFindings)
    $sys32 = [Environment]::GetFolderPath('System')
    foreach ($scriptName in $script:KnownMaliciousScripts) {
        $fullPath     = Join-Path $sys32 $scriptName
        if (Test-Path -LiteralPath $fullPath) {
            $alreadyAdded = $ScriptFindings.Value | Where-Object { $_.FilePath -eq $fullPath }
            if (-not $alreadyAdded) {
                $ScriptFindings.Value += [PSCustomObject]@{
                    Category    = 'PayloadScript'
                    FilePath    = $fullPath
                    Description = 'Known browser hijacker payload dropped in Windows System32.'
                }
            }
        }
    }
}

# ============================================================
# FIREFOX DISTRIBUTION POLICY SCANNER
# ============================================================

function Invoke-FirefoxPolicyScan {
    param([ref]$Findings)
    $programFiles    = [Environment]::GetFolderPath('ProgramFiles')
    $programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')
    foreach ($base in @($programFiles, $programFilesX86)) {
        $polPath = Join-Path $base 'Mozilla Firefox\distribution\policies.json'
        if (Test-Path -LiteralPath $polPath) {
            $Findings.Value += [PSCustomObject]@{
                Category    = 'FirefoxPolicy'
                FilePath    = $polPath
                Description = 'Firefox distribution-level policies.json overrides search engine and homepage.'
            }
        }
    }
}

# ============================================================
# SHORTCUT (.LNK) HIJACK SCANNER
# ============================================================

function Test-ArgumentContainsUrl {
    param([string]$Arguments)
    if ([string]::IsNullOrWhiteSpace($Arguments)) { return $false }
    if (($Arguments -like '*http://*') -or ($Arguments -like '*https://*')) { return $true }

    $parts = $Arguments -split '\s+' | Where-Object { $_.Trim() -ne '' }
    foreach ($part in $parts) {
        if ($part.StartsWith('-') -or $part.StartsWith('/')) { continue }
        if ($part.Contains('.') -and
            (-not $part.Contains('\')) -and
            (-not $part.Contains('/')) -and
            ($part -notmatch '\.(exe|dll|lnk)$')) {
            return $true
        }
    }
    return $false
}

function Remove-UrlsFromArguments {
    param([string]$Arguments)
    if ([string]::IsNullOrWhiteSpace($Arguments)) { return '' }

    $parts  = $Arguments -split '\s+' | Where-Object { $_.Trim() -ne '' }
    $result = [System.Collections.Generic.List[string]]::new()

    foreach ($part in $parts) {
        if (($part -like '*http://*') -or ($part -like '*https://*')) { continue }
        if ((-not $part.StartsWith('-')) -and (-not $part.StartsWith('/'))) {
            if ($part.Contains('.') -and
                (-not $part.Contains('\')) -and
                (-not $part.Contains('/')) -and
                ($part -notmatch '\.(exe|dll|lnk)$')) { continue }
        }
        $result.Add($part)
    }
    return ($result -join ' ')
}

function Invoke-ShortcutScan {
    param([string[]]$Directories, [ref]$Findings)

    $shell = New-Object -ComObject WScript.Shell
    foreach ($dir in $Directories) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        try {
            $lnkFiles = Get-ChildItem -LiteralPath $dir -Filter '*.lnk' -Recurse -File `
                        -ErrorAction SilentlyContinue
            foreach ($lnkFile in $lnkFiles) {
                try {
                    $sc      = $shell.CreateShortcut($lnkFile.FullName)
                    $tgt     = $sc.TargetPath
                    $args    = $sc.Arguments

                    if ([string]::IsNullOrEmpty($tgt)) { continue }
                    $exeName = [IO.Path]::GetFileName($tgt).ToLower()
                    if ($script:BrowserExecutables -notcontains $exeName) { continue }
                    if (-not (Test-ArgumentContainsUrl -Arguments $args)) { continue }

                    $Findings.Value += [PSCustomObject]@{
                        Category     = 'Shortcut'
                        FilePath     = $lnkFile.FullName
                        Target       = $tgt
                        OriginalArgs = $args
                        CleanArgs    = (Remove-UrlsFromArguments -Arguments $args)
                    }
                } catch {}
            }
        } catch {}
    }
}

# ============================================================
# BACKUP MODULE
# ============================================================

function New-BackupDirectory {
    $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
    $script:BackupDir = Join-Path $script:BackupRoot "NextgeekerBackup_$ts"
    New-Item -Path $script:BackupDir                        -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $script:BackupDir 'Files')    -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $script:BackupDir 'Registry') -ItemType Directory -Force | Out-Null
    Write-Log -Level Success -Message "Backup directory created: $script:BackupDir"
}

function New-SystemRestorePoint {
    Write-Log -Level Info -Message 'Requesting Windows System Restore Point creation...'
    try {
        Checkpoint-Computer -Description 'Nextgeeker-Annihilator Pre-Removal Backup' `
                            -RestorePointType 'ModifySettings' -ErrorAction Stop
        Write-Log -Level Success -Message 'System Restore Point created successfully.'
    } catch {
        Write-Log -Level Warn -Message "Restore Point skipped: $($_.Exception.Message)"
    }
}

function Export-RegistryKeyToFile {
    param([string]$Hive, [string]$SubKey)
    $psPath = if ($Hive -eq 'HKLM') { "HKLM:\$SubKey" } else { "HKCU:\$SubKey" }
    if (-not (Test-Path -LiteralPath $psPath)) { return }

    $safeFileName = ($SubKey -replace '\\','_') + '.reg'
    $destFile     = Join-Path $script:BackupDir "Registry\${Hive}_${safeFileName}"
    $regHivePath  = "$Hive\$SubKey"
    try {
        $proc = Start-Process -FilePath 'reg.exe' `
                              -ArgumentList "export `"$regHivePath`" `"$destFile`" /y" `
                              -NoNewWindow -PassThru -Wait -ErrorAction Stop
        if ($proc.ExitCode -eq 0) {
            Write-Log -Level Info -Message "Registry exported: $Hive\$SubKey"
        } else {
            Write-Log -Level Warn -Message "reg.exe failed for $Hive\$SubKey (exit $($proc.ExitCode))"
        }
    } catch {
        Write-Log -Level Warn -Message "Export error for $Hive\$SubKey : $($_.Exception.Message)"
    }
}

function Copy-ItemToBackup {
    param([string]$SourcePath)
    if (-not (Test-Path -LiteralPath $SourcePath)) { return }
    $destBase = Join-Path $script:BackupDir 'Files'
    try {
        if (Test-Path -LiteralPath $SourcePath -PathType Leaf) {
            Copy-Item -LiteralPath $SourcePath -Destination $destBase -Force -ErrorAction Stop
            Write-Log -Level Info -Message "File backed up: $(Split-Path $SourcePath -Leaf)"
        } else {
            $folderName = Split-Path $SourcePath -Leaf
            $destFolder = Join-Path $destBase $folderName
            Copy-Item -LiteralPath $SourcePath -Destination $destFolder -Recurse -Force -ErrorAction Stop
            Write-Log -Level Info -Message "Directory backed up: $folderName"
        }
    } catch {
        Write-Log -Level Warn -Message "Backup copy failed for $SourcePath : $($_.Exception.Message)"
    }
}

function Invoke-FullBackup {
    Write-SectionHeader 'BACKUP AND RESTORE POINT'
    New-BackupDirectory
    New-SystemRestorePoint

    Write-Log -Level Info -Message 'Exporting browser policy registry hives...'
    foreach ($entry in $script:PolicyHiveMap) {
        Export-RegistryKeyToFile -Hive $entry.Hive -SubKey $entry.Path
    }
    Export-RegistryKeyToFile -Hive 'HKLM' `
        -SubKey 'SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell'

    Write-Log -Level Info -Message 'Backing up Group Policy template directories...'
    $sys32 = [Environment]::GetFolderPath('System')
    Copy-ItemToBackup -SourcePath (Join-Path $sys32 'GroupPolicy')
    Copy-ItemToBackup -SourcePath (Join-Path $sys32 'GroupPolicyUsers')

    Write-Log -Level Success -Message "All backup artefacts saved to: $script:BackupDir"
}

# ============================================================
# ERADICATION MODULE
# ============================================================

function Stop-BrowserProcesses {
    Write-Log -Level Info -Message 'Terminating active browser and scripting processes...'
    foreach ($procName in $script:BrowserProcessNames) {
        $instances = Get-Process -Name $procName -ErrorAction SilentlyContinue
        if ($instances) {
            Write-Log -Level Info -Message "Stopping ${procName}.exe ($($instances.Count) instances)"
            $instances | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 600
        }
    }
}

function Remove-RegistryPolicies {
    Write-Log -Level Info -Message 'Removing browser policy registry trees...'
    foreach ($entry in $script:PolicyHiveMap) {
        $psPath = if ($entry.Hive -eq 'HKLM') { "HKLM:\$($entry.Path)" } else { "HKCU:\$($entry.Path)" }
        if (-not (Test-Path -LiteralPath $psPath)) { continue }
        try {
            Remove-Item -LiteralPath $psPath -Recurse -Force -ErrorAction Stop
            Write-Log -Level Success -Message "Deleted: $($entry.Hive)\$($entry.Path)"
        } catch {
            Write-Log -Level Warn -Message "Could not delete $($entry.Hive)\$($entry.Path): $($_.Exception.Message)"
        }
    }

    $pwshKey = 'HKLM:\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell'
    if (Test-Path -LiteralPath $pwshKey) {
        try {
            Set-ItemProperty -LiteralPath $pwshKey -Name 'ExecutionPolicy' -Value 'Restricted' -Force
            Write-Log -Level Success -Message 'PowerShell ExecutionPolicy restored to Restricted.'
        } catch {
            Write-Log -Level Warn -Message "Could not reset ExecutionPolicy: $($_.Exception.Message)"
        }
    }
}

function Remove-GroupPolicies {
    param([object[]]$GpFindings)
    Write-Log -Level Info -Message 'Removing local Group Policy template directories...'
    foreach ($gp in $GpFindings) {
        Copy-ItemToBackup -SourcePath $gp.FolderPath
        try {
            Remove-Item -LiteralPath $gp.FolderPath -Recurse -Force -ErrorAction Stop
            Write-Log -Level Success -Message "Deleted GP folder: $($gp.FolderPath)"
        } catch {
            Write-Log -Level Warn -Message "Could not remove $($gp.FolderPath): $($_.Exception.Message)"
        }
    }
    Write-Log -Level Info -Message 'Forcing group policy refresh...'
    try {
        Start-Process -FilePath 'gpupdate.exe' -ArgumentList '/force' -NoNewWindow -PassThru -Wait |
            Out-Null
        Write-Log -Level Success -Message 'gpupdate /force completed.'
    } catch {
        Write-Log -Level Warn -Message "gpupdate failed: $($_.Exception.Message)"
    }
}

function Remove-ScheduledTasks {
    param([object[]]$TaskFindings)
    Write-Log -Level Info -Message 'Deregistering malicious scheduled tasks...'
    foreach ($task in $TaskFindings) {
        try {
            $proc = Start-Process -FilePath 'schtasks.exe' `
                                  -ArgumentList "/Delete /TN `"$($task.TaskName)`" /F" `
                                  -NoNewWindow -PassThru -Wait
            if ($proc.ExitCode -eq 0) {
                Write-Log -Level Success -Message "Task unregistered: $($task.TaskName)"
            } else {
                Write-Log -Level Warn -Message 'schtasks.exe failed, attempting direct file removal...'
                if (Test-Path -LiteralPath $task.FilePath) {
                    Remove-Item -LiteralPath $task.FilePath -Force
                    Write-Log -Level Success -Message "Task XML deleted: $($task.FilePath)"
                }
            }
        } catch {
            Write-Log -Level Warn -Message "Task removal error ($($task.TaskName)): $($_.Exception.Message)"
        }
    }
}

function Remove-PayloadScripts {
    param([object[]]$ScriptFindings, [object[]]$FfFindings)
    Write-Log -Level Info -Message 'Deleting payload scripts and Firefox policy files...'

    foreach ($s in $ScriptFindings) {
        if (-not (Test-Path -LiteralPath $s.FilePath)) { continue }
        Copy-ItemToBackup -SourcePath $s.FilePath
        try {
            Remove-Item -LiteralPath $s.FilePath -Force -ErrorAction Stop
            Write-Log -Level Success -Message "Deleted payload: $(Split-Path $s.FilePath -Leaf)"
        } catch {
            Write-Log -Level Warn -Message "Could not delete $($s.FilePath): $($_.Exception.Message)"
        }
    }

    foreach ($ff in $FfFindings) {
        if (-not (Test-Path -LiteralPath $ff.FilePath)) { continue }
        Copy-ItemToBackup -SourcePath $ff.FilePath
        try {
            Remove-Item -LiteralPath $ff.FilePath -Force -ErrorAction Stop
            Write-Log -Level Success -Message "Deleted Firefox policy: $($ff.FilePath)"
            $parentDir = Split-Path $ff.FilePath -Parent
            if (Test-Path -LiteralPath $parentDir) {
                $remaining = Get-ChildItem -LiteralPath $parentDir -ErrorAction SilentlyContinue
                if (-not $remaining) {
                    Remove-Item -LiteralPath $parentDir -Force -ErrorAction SilentlyContinue
                    Write-Log -Level Info -Message "Cleaned empty directory: $parentDir"
                }
            }
        } catch {
            Write-Log -Level Warn -Message "Could not delete $($ff.FilePath): $($_.Exception.Message)"
        }
    }
}

function Remove-AnomalousExtensions {
    param([object[]]$ExtFindings)
    Write-Log -Level Info -Message 'Removing anomalous browser extension directories...'
    foreach ($ext in $ExtFindings) {
        if (-not (Test-Path -LiteralPath $ext.FolderPath)) { continue }
        $safeLabel = "$($ext.Browser)_$($ext.Profile)_$($ext.ExtensionId)" -replace '[\\/:*?"<>|]','_'
        $destDir   = Join-Path $script:BackupDir "Files\$safeLabel"
        try {
            Copy-Item -LiteralPath $ext.FolderPath -Destination $destDir -Recurse -Force -ErrorAction Stop
            Remove-Item -LiteralPath $ext.FolderPath -Recurse -Force -ErrorAction Stop
            Write-Log -Level Success -Message "Extension purged: [$($ext.Browser)] $($ext.ExtensionId) ($($ext.ExtName))"
        } catch {
            Write-Log -Level Warn -Message "Could not remove $($ext.FolderPath): $($_.Exception.Message)"
        }
    }
}

function Repair-HijackedShortcuts {
    param([object[]]$ShortcutFindings)
    Write-Log -Level Info -Message 'Sanitizing hijacked browser shortcuts...'
    $shell = New-Object -ComObject WScript.Shell
    foreach ($lnk in $ShortcutFindings) {
        try {
            $sc           = $shell.CreateShortcut($lnk.FilePath)
            $sc.Arguments = $lnk.CleanArgs
            $sc.Save()
            Write-Log -Level Success -Message "Shortcut cleaned: $(Split-Path $lnk.FilePath -Leaf)"
        } catch {
            Write-Log -Level Warn -Message "Could not fix shortcut $($lnk.FilePath): $($_.Exception.Message)"
        }
    }
}

# ============================================================
# REPORT PRINTER
# ============================================================

function Write-FullReport {
    param(
        [object[]]$RegFindings,
        [object[]]$GpFindings,
        [object[]]$ExtFindings,
        [object[]]$TaskFindings,
        [object[]]$ScriptFindings,
        [object[]]$FfFindings,
        [object[]]$LnkFindings
    )

    Write-Host ''
    Write-Host '  ========================================================' -ForegroundColor Cyan
    Write-Host '                        SCAN REPORT' -ForegroundColor Cyan
    Write-Host '  ========================================================' -ForegroundColor Cyan

    # 1. Registry Policies
    Write-Host ''
    Write-Host '  [1/7] Registry Policy Anomalies' -ForegroundColor White
    if ($RegFindings.Count -gt 0) {
        Write-Host "        $($RegFindings.Count) finding(s) detected:" -ForegroundColor Red
        foreach ($r in $RegFindings) {
            Write-Host "        . [$($r.Hive)] $($r.KeyPath)" -ForegroundColor White
            Write-Host "          Value : $($r.ValueName) = $($r.ValueData)" -ForegroundColor DarkYellow
            Write-Host "          Risk  : $($r.Description)" -ForegroundColor DarkYellow
        }
    } else {
        Write-Host '        Clean - no unauthorized registry policies found.' -ForegroundColor Green
    }

    # 2. Group Policy
    Write-Host ''
    Write-Host '  [2/7] Local Group Policy Directories' -ForegroundColor White
    if ($GpFindings.Count -gt 0) {
        Write-Host "        $($GpFindings.Count) folder(s) detected:" -ForegroundColor Red
        foreach ($g in $GpFindings) {
            Write-Host "        . $($g.FolderPath)" -ForegroundColor White
            Write-Host "          Risk : $($g.Description)" -ForegroundColor DarkYellow
        }
    } else {
        Write-Host '        Clean - no policy template directories present.' -ForegroundColor Green
    }

    # 3. Extensions
    Write-Host ''
    Write-Host '  [3/7] Browser Extension Anomalies' -ForegroundColor White
    if ($ExtFindings.Count -gt 0) {
        Write-Host "        $($ExtFindings.Count) anomalous extension(s):" -ForegroundColor Red
        foreach ($e in $ExtFindings) {
            Write-Host "        . [$($e.Browser)] Profile: $($e.Profile)" -ForegroundColor White
            Write-Host "          ID        : $($e.ExtensionId)" -ForegroundColor DarkYellow
            Write-Host "          Name      : $($e.ExtName) v$($e.Version)" -ForegroundColor DarkYellow
            Write-Host "          UpdateURL : $($e.UpdateUrl)" -ForegroundColor DarkYellow
            Write-Host "          Tags      : $($e.Tags)" -ForegroundColor DarkYellow
        }
    } else {
        Write-Host '        Clean - no orphaned or policy-forced extensions found.' -ForegroundColor Green
    }

    # 4. Scheduled Tasks
    Write-Host ''
    Write-Host '  [4/7] Malicious Scheduled Tasks' -ForegroundColor White
    if ($TaskFindings.Count -gt 0) {
        Write-Host "        $($TaskFindings.Count) suspicious task(s):" -ForegroundColor Red
        foreach ($t in $TaskFindings) {
            Write-Host "        . Name   : $($t.TaskName)" -ForegroundColor White
            Write-Host "          Reason : $($t.Reason)" -ForegroundColor DarkYellow
        }
    } else {
        Write-Host '        Clean - no malicious scheduled tasks found.' -ForegroundColor Green
    }

    # 5. Script Payloads
    Write-Host ''
    Write-Host '  [5/7] Script Payload Files' -ForegroundColor White
    if ($ScriptFindings.Count -gt 0) {
        Write-Host "        $($ScriptFindings.Count) script file(s) found:" -ForegroundColor Red
        foreach ($s in $ScriptFindings) {
            Write-Host "        . $($s.FilePath)" -ForegroundColor White
            Write-Host "          Desc : $($s.Description)" -ForegroundColor DarkYellow
        }
    } else {
        Write-Host '        Clean - no payload scripts detected in system folders.' -ForegroundColor Green
    }

    # 6. Firefox Policies
    Write-Host ''
    Write-Host '  [6/7] Firefox Distribution Policies' -ForegroundColor White
    if ($FfFindings.Count -gt 0) {
        Write-Host "        $($FfFindings.Count) file(s) found:" -ForegroundColor Red
        foreach ($ff in $FfFindings) {
            Write-Host "        . $($ff.FilePath)" -ForegroundColor White
            Write-Host "          Desc : $($ff.Description)" -ForegroundColor DarkYellow
        }
    } else {
        Write-Host '        Clean - no Firefox distribution policies detected.' -ForegroundColor Green
    }

    # 7. Shortcuts
    Write-Host ''
    Write-Host '  [7/7] Hijacked Browser Shortcuts' -ForegroundColor White
    if ($LnkFindings.Count -gt 0) {
        Write-Host "        $($LnkFindings.Count) shortcut(s) corrupted:" -ForegroundColor Red
        foreach ($lnk in $LnkFindings) {
            Write-Host "        . $($lnk.FilePath)" -ForegroundColor White
            Write-Host "          Target : $($lnk.Target)" -ForegroundColor DarkYellow
            Write-Host "          Args   : $($lnk.OriginalArgs)" -ForegroundColor DarkYellow
            Write-Host "          Fixed  : $($lnk.CleanArgs)" -ForegroundColor DarkYellow
        }
    } else {
        Write-Host '        Clean - all browser shortcuts are unmodified.' -ForegroundColor Green
    }

    Write-Host ''
    Write-Host '  ========================================================' -ForegroundColor Cyan
    Write-Host ''
}

# ============================================================
# POST-REMOVAL NOTICE
# ============================================================

function Write-PostRemovalNotice {
    $backupNote = "  Backup location: $script:BackupDir"
    Write-Host ''
    Write-Host '  ========================================================' -ForegroundColor Green
    Write-Host '  ERADICATION COMPLETE' -ForegroundColor Green
    Write-Host '  ========================================================' -ForegroundColor Green
    Write-Host ''
    Write-Host '  MANDATORY POST-REMOVAL STEPS (complete all three):' -ForegroundColor Yellow
    Write-Host '  ----------------------------------------------------' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  1. BROWSER CLOUD SYNC ISOLATION' -ForegroundColor Yellow
    Write-Host '     The hijacker syncs its config to your browser account.' -ForegroundColor Gray
    Write-Host '     Purge the cloud cache BEFORE opening any browser again.' -ForegroundColor Gray
    Write-Host '     - Chrome  : Profile icon > Sync is on > Turn Off >' -ForegroundColor Gray
    Write-Host '                 Delete Data (on Google Dashboard)' -ForegroundColor Gray
    Write-Host '     - Edge    : edge://settings/profiles/sync > Turn off sync' -ForegroundColor Gray
    Write-Host '     - Firefox : Settings > Account > Disconnect profile sync' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  2. HARD BROWSER PROFILE RESET' -ForegroundColor Yellow
    Write-Host '     - Chrome  : Settings > Reset settings > Restore to original defaults' -ForegroundColor Gray
    Write-Host '     - Edge    : Settings > Reset settings > Restore to default values' -ForegroundColor Gray
    Write-Host '     - Firefox : about:support > Refresh Firefox' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  3. INSTALLED APPS AUDIT' -ForegroundColor Yellow
    Write-Host '     - Open Settings > Apps > Installed apps' -ForegroundColor Gray
    Write-Host '     - Sort by Install date' -ForegroundColor Gray
    Write-Host '     - Remove any unrecognised program installed near the' -ForegroundColor Gray
    Write-Host '       date when the hijacking first appeared.' -ForegroundColor Gray
    Write-Host ''
    Write-Host $backupNote -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  ========================================================' -ForegroundColor Green
}

# ============================================================
# MAIN EXECUTION ENTRY POINT
# ============================================================

Write-Banner

if (-not (Test-IsAdmin)) { Invoke-SelfElevate }

if ($BackupOnly) {
    Write-Log -Level Section -Message 'BACKUP-ONLY MODE'
    Invoke-FullBackup
    Write-Log -Level Success -Message 'Backup complete. No system changes were made.'
    exit 0
}

# Phase 1: Scan
Write-Log -Level Section -Message 'PHASE 1 -- BEHAVIORAL ANOMALY SCAN'

$regFindings    = [System.Collections.Generic.List[object]]::new()
$forcedExtIds   = [System.Collections.Generic.List[string]]::new()
$gpFindings     = [System.Collections.Generic.List[object]]::new()
$extFindings    = [System.Collections.Generic.List[object]]::new()
$taskFindings   = [System.Collections.Generic.List[object]]::new()
$scriptFindings = [System.Collections.Generic.List[object]]::new()
$ffFindings     = [System.Collections.Generic.List[object]]::new()
$lnkFindings    = [System.Collections.Generic.List[object]]::new()

Write-Log -Level Info -Message 'Scanning registry policy hives...'
Invoke-RegistryScan -Findings ([ref]$regFindings) -ForcedExtIds ([ref]$forcedExtIds)

Write-Log -Level Info -Message 'Scanning local Group Policy directories...'
Invoke-GroupPolicyScan -Findings ([ref]$gpFindings)

Write-Log -Level Info -Message 'Scanning Chromium browser extension profiles...'
Invoke-ExtensionScan -ForcedExtIds $forcedExtIds -Findings ([ref]$extFindings)

Write-Log -Level Info -Message 'Parsing Task Scheduler XML definitions...'
Invoke-TaskScan -TaskFindings ([ref]$taskFindings) -ScriptFindings ([ref]$scriptFindings)

Write-Log -Level Info -Message 'Auditing known payload scripts in System32...'
Invoke-ScriptPayloadScan -ScriptFindings ([ref]$scriptFindings)

Write-Log -Level Info -Message 'Scanning Firefox distribution policy files...'
Invoke-FirefoxPolicyScan -Findings ([ref]$ffFindings)

Write-Log -Level Info -Message 'Scanning browser shortcut target arguments...'
$shortcutDirs = @(
    [Environment]::GetFolderPath('Desktop')
    [Environment]::GetFolderPath('CommonDesktopDirectory')
    [Environment]::GetFolderPath('StartMenu')
    [Environment]::GetFolderPath('CommonStartMenu')
    (Join-Path ([Environment]::GetFolderPath('ApplicationData')) `
               'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar')
)
Invoke-ShortcutScan -Directories $shortcutDirs -Findings ([ref]$lnkFindings)

# Phase 2: Report
Write-Log -Level Section -Message 'PHASE 2 -- SCAN REPORT'

Write-FullReport `
    -RegFindings    $regFindings    `
    -GpFindings     $gpFindings     `
    -ExtFindings    $extFindings    `
    -TaskFindings   $taskFindings   `
    -ScriptFindings $scriptFindings `
    -FfFindings     $ffFindings     `
    -LnkFindings    $lnkFindings

$totalThreats = $regFindings.Count    + $gpFindings.Count  + $extFindings.Count +
                $taskFindings.Count   + $scriptFindings.Count +
                $ffFindings.Count     + $lnkFindings.Count

if ($totalThreats -eq 0) {
    Write-Log -Level Success -Message 'No behavioral anomalies or persistence vectors detected. System is clean.'
    exit 0
}

Write-Log -Level Warn -Message "$totalThreats total threat indicator(s) detected across all scan categories."

if ($ScanOnly) {
    Write-Log -Level Info -Message 'ScanOnly mode active. Exiting without making system modifications.'
    exit 0
}

# Phase 3: Confirm
Write-Log -Level Section -Message 'PHASE 3 -- ERADICATION CONFIRMATION'

$confirmed = $Force
if (-not $confirmed) {
    Write-Host ''
    Write-Host '  All flagged items will be backed up before deletion.' -ForegroundColor Cyan
    Write-Host '  A System Restore Point will be created first.' -ForegroundColor Cyan
    Write-Host ''
    $response  = Read-Host '  Proceed with eradication and security hardening? [y/N]'
    $confirmed = ($response -eq 'y' -or $response -eq 'Y')
}

if (-not $confirmed) {
    Write-Log -Level Warn -Message 'Eradication aborted by user.'
    exit 0
}

# Phase 4: Eradicate
Write-Log -Level Section -Message 'PHASE 4 -- ERADICATION'

Write-Log -Level Info -Message '[1/8] Stopping browser processes...'
Stop-BrowserProcesses

Write-Log -Level Info -Message '[2/8] Creating backup and restore point...'
Invoke-FullBackup

Write-Log -Level Info -Message '[3/8] Removing registry policy trees...'
Remove-RegistryPolicies

Write-Log -Level Info -Message '[4/8] Removing local Group Policy templates...'
Remove-GroupPolicies -GpFindings $gpFindings

Write-Log -Level Info -Message '[5/8] Deleting malicious scheduled tasks...'
Remove-ScheduledTasks -TaskFindings $taskFindings

Write-Log -Level Info -Message '[6/8] Deleting payload scripts and Firefox policies...'
Remove-PayloadScripts -ScriptFindings $scriptFindings -FfFindings $ffFindings

Write-Log -Level Info -Message '[7/8] Purging anomalous extension directories...'
Remove-AnomalousExtensions -ExtFindings $extFindings

Write-Log -Level Info -Message '[8/8] Repairing hijacked browser shortcuts...'
Repair-HijackedShortcuts -ShortcutFindings $lnkFindings

Write-PostRemovalNotice
exit 0
