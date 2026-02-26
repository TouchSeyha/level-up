<#
.SYNOPSIS
    level-up — bulk tool updater for Windows 11 / PowerShell.

.DESCRIPTION
    Manage and run update commands for all your development tools from a single
    command. Supports adding, removing, listing, and running saved entries, plus
    profile integration and health checks.

.EXAMPLE
    level-up add
    level-up list
    level-up run codex
    level-up all
    level-up doctor
    level-up alias --install

.NOTES
    Compatible with PowerShell 5.1 and PowerShell 7+.
    Config  : %LOCALAPPDATA%\level-up\commands.json
    Logs    : %LOCALAPPDATA%\level-up\logs\
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Action = 'help',

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Names = @()
)

$ErrorActionPreference = 'Continue'
if ($null -eq $Names) { $Names = @() }

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
$ConfigDir  = "$env:LOCALAPPDATA\level-up"
$ConfigFile = "$ConfigDir\commands.json"
$LogDir     = "$ConfigDir\logs"

# ---------------------------------------------------------------------------
# Config helpers
# ---------------------------------------------------------------------------
function Get-Config {
    if (-not (Test-Path $ConfigDir)) {
        New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
    }
    if (-not (Test-Path $ConfigFile)) {
        [PSCustomObject]@{ commands = @() } |
            ConvertTo-Json -Depth 5 |
            Set-Content -Path $ConfigFile -Encoding UTF8
    }
    $raw    = Get-Content -Path $ConfigFile -Raw -Encoding UTF8
    $config = $raw | ConvertFrom-Json

    # Migrate: ensure every command has the 'enabled' field (backward compat)
    $config.commands = @($config.commands | ForEach-Object {
        if ($null -eq $_.PSObject.Properties['enabled']) {
            $_ | Add-Member -NotePropertyName 'enabled' -NotePropertyValue $true -Force
        }
        $_
    })

    return $config
}

function Save-Config {
    param([PSCustomObject]$Config)
    if (-not (Test-Path $ConfigDir)) {
        New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
    }
    $Config | ConvertTo-Json -Depth 5 | Set-Content -Path $ConfigFile -Encoding UTF8
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
$script:CurrentLogFile = $null

function New-RunLog {
    param([string]$Label)
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
    $ts = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $script:CurrentLogFile = "$LogDir\$ts.log"
    $header = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] === level-up $Label ==="
    Add-Content -Path $script:CurrentLogFile -Value $header -Encoding UTF8
}

function Write-LogLine {
    param([string]$Line)
    if ($script:CurrentLogFile) {
        Add-Content -Path $script:CurrentLogFile -Value $Line -Encoding UTF8
    }
}

function Close-RunLog {
    param([int]$Passed, [int]$Failed)
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] === SUMMARY: $Passed passed, $Failed failed ==="
    Write-LogLine $line
}

function InterruptExitCode {
    param([int]$Code)
    return ($Code -eq 130 -or $Code -eq -1073741510 -or $Code -eq 3221225786)
}

function CancellationError {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)

    if ($null -eq $ErrorRecord) { return $false }

    $exception = $ErrorRecord.Exception
    if ($exception -is [System.Management.Automation.PipelineStoppedException]) { return $true }
    if ($exception -is [System.OperationCanceledException]) { return $true }

    if ($ErrorRecord.FullyQualifiedErrorId -match 'PipelineStopped|ConsoleCancelEvent|OperationStopped') {
        return $true
    }

    $message = ""
    if ($null -ne $exception -and -not [string]::IsNullOrEmpty($exception.Message)) {
        $message = $exception.Message
    }

    return ($message -match 'canceled by the user|cancelled by the user|pipeline has been stopped')
}

# ---------------------------------------------------------------------------
# Run engine
# ---------------------------------------------------------------------------
function Invoke-SingleCommand {
    param(
        [string]$Name,
        [string]$Command
    )

    Write-Host ""
    Write-Host "==> $Name" -ForegroundColor Cyan
    Write-Host "    $Command" -ForegroundColor DarkGray
    Write-LogLine "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] --> $Name`: $Command"

    $start    = Get-Date
    $exitCode = 0

    try {
        # | Out-Host routes stdout to the terminal immediately without
        # contaminating this function's output pipeline (which would corrupt
        # the integer return value when the command prints text).
        # $LASTEXITCODE is set by the external process and is NOT shadowed
        # here — no local assignment that would hide the global automatic var.
        Invoke-Expression $Command | Out-Host
        if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            if (InterruptExitCode -Code $LASTEXITCODE) {
                $exitCode = 130
            } else {
                $exitCode = $LASTEXITCODE
            }
        }
    } catch {
        if (CancellationError -ErrorRecord $_) {
            $exitCode = 130
        } else {
            $exitCode = 1
            Write-Host "    ERROR: $_" -ForegroundColor Red
        }
    }

    $duration = [int]((Get-Date) - $start).TotalSeconds
    $ts2 = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')]"

    if ($exitCode -eq 0) {
        Write-Host "    [OK] exit $exitCode  ($($duration)s)" -ForegroundColor Green
        Write-LogLine "$ts2 <-- $Name`: EXIT $exitCode ($($duration)s)"
    } elseif ($exitCode -eq 130) {
        Write-Host "    [INTERRUPTED] Ctrl+C  ($($duration)s)" -ForegroundColor Yellow
        Write-LogLine "$ts2 <-- $Name`: INTERRUPTED ($($duration)s)"
    } else {
        Write-Host "    [FAILED] exit $exitCode  ($($duration)s)" -ForegroundColor Red
        Write-LogLine "$ts2 <-- $Name`: EXIT $exitCode ($($duration)s) [FAILED]"
    }

    return $exitCode
}

function Invoke-CommandList {
    param([array]$Entries, [string]$Label)

    if ($Entries.Count -eq 0) {
        Write-Host "No commands to run." -ForegroundColor Yellow
        return
    }

    New-RunLog $Label

    $passed      = 0
    $failed      = 0
    $failedNames = @()
    $interrupted = $false

    foreach ($entry in $Entries) {
        $code = Invoke-SingleCommand -Name $entry.name -Command $entry.command
        if ($code -eq 0) {
            $passed++
        } elseif ($code -eq 130) {
            $failed++
            $failedNames += $entry.name
            $interrupted = $true
            break
        } else {
            $failed++
            $failedNames += $entry.name
        }
    }

    Close-RunLog -Passed $passed -Failed $failed

    Write-Host ""
    Write-Host "--- Summary ---" -ForegroundColor White
    Write-Host ("  Passed : {0}" -f $passed) -ForegroundColor Green

    if ($failed -gt 0) {
        Write-Host ("  Failed : {0}  ({1})" -f $failed, ($failedNames -join ', ')) -ForegroundColor Red
        Write-Host "  Log    : $script:CurrentLogFile" -ForegroundColor DarkGray
        Write-Host ""
        if ($interrupted) {
            Write-Host "  Stopped: interrupted by user (Ctrl+C)" -ForegroundColor Yellow
            Write-Host ""
            exit 130
        }
        exit 1
    } else {
        Write-Host ("  Failed : {0}" -f $failed) -ForegroundColor Green
        Write-Host "  Log    : $script:CurrentLogFile" -ForegroundColor DarkGray
        Write-Host ""
    }
}

function Invoke-AllCommands {
    $config = Get-Config
    $active = @($config.commands | Where-Object { $_.enabled -ne $false })

    if ($active.Count -eq 0 -and @($config.commands).Count -gt 0) {
        Write-Host "All entries are disabled. Use 'level-up enable <name>' to re-enable one." -ForegroundColor Yellow
        return
    }

    Invoke-CommandList -Entries $active -Label 'all'
}

function Invoke-NamedCommands {
    param([string[]]$NameList)

    if ($NameList.Count -eq 0) {
        Write-Host "Usage: level-up run <name> [name...]" -ForegroundColor Yellow
        return
    }

    $config  = Get-Config
    $entries = @()

    foreach ($n in $NameList) {
        $entry = @($config.commands) | Where-Object { $_.name -eq $n }
        if ($null -eq $entry -or @($entry).Count -eq 0) {
            Write-Host "Not found: '$n'" -ForegroundColor Red
        } elseif ($entry[0].enabled -eq $false) {
            Write-Host "  [DISABLED] '$n' is disabled. Use 'level-up enable $n' to re-enable it." -ForegroundColor Yellow
        } else {
            $entries += $entry
        }
    }

    if ($entries.Count -eq 0) {
        Write-Host "No matching entries found." -ForegroundColor Red
        exit 1
    }

    Invoke-CommandList -Entries $entries -Label "run $($NameList -join ' ')"
}

# ---------------------------------------------------------------------------
# CRUD
# ---------------------------------------------------------------------------
function Read-YesNo {
    param([string]$Prompt)

    while ($true) {
        $answer = (Read-Host $Prompt).Trim().ToUpperInvariant()
        if ($answer -eq 'Y' -or $answer -eq 'YES') { return $true }
        if ($answer -eq 'N' -or $answer -eq 'NO') { return $false }
        Write-Host "Please enter y or n." -ForegroundColor Yellow
    }
}

function Add-Entry {
    while ($true) {
        $config = Get-Config

        Write-Host ""
        Write-Host "Add a new update command" -ForegroundColor Cyan
        Write-Host ""

        $name = (Read-Host "  Name (e.g. codex, claude)").Trim()
        if ([string]::IsNullOrEmpty($name)) {
            Write-Host "Name cannot be empty." -ForegroundColor Red
            return
        }

        $existing = @($config.commands) | Where-Object { $_.name -eq $name }
        if ($null -ne $existing -and @($existing).Count -gt 0) {
            Write-Host "Entry '$name' already exists. Use 'level-up remove $name' first." -ForegroundColor Red
            return
        }

        $command = (Read-Host "  Command (e.g. npm i -g @openai/codex@latest)").Trim()
        if ([string]::IsNullOrEmpty($command)) {
            Write-Host "Command cannot be empty." -ForegroundColor Red
            return
        }

        $newEntry         = [PSCustomObject]@{ name = $name; command = $command; enabled = $true }
        $config.commands  = @($config.commands) + $newEntry
        Save-Config $config

        Write-Host ""
        Write-Host "  Added: $name" -ForegroundColor Green
        Write-Host "         $command" -ForegroundColor DarkGray
        Write-Host ""

        $addMore = Read-YesNo -Prompt "Add another? (y/n)"
        if (-not $addMore) { return }
    }
}

function Remove-Entry {
    param([string]$Name)

    if ([string]::IsNullOrEmpty($Name)) {
        Write-Host "Usage: level-up remove <name>" -ForegroundColor Yellow
        return
    }

    $currentName = $Name
    while ($true) {
        $config = Get-Config
        $before = @($config.commands).Count
        $config.commands = @($config.commands | Where-Object { $_.name -ne $currentName })
        $after  = @($config.commands).Count

        if ($before -eq $after) {
            Write-Host "Not found: '$currentName'" -ForegroundColor Red
            exit 1
        }

        Save-Config $config
        Write-Host "Removed: $currentName" -ForegroundColor Green

        $removeMore = Read-YesNo -Prompt "Delete another? (y/n)"
        if (-not $removeMore) { return }

        $nextName = (Read-Host "Name to delete").Trim()
        if ([string]::IsNullOrEmpty($nextName)) {
            Write-Host "Name cannot be empty." -ForegroundColor Red
            return
        }

        $currentName = $nextName
    }
}

function Set-EntryEnabled {
    param([string]$Name, [bool]$Enabled)

    if ([string]::IsNullOrEmpty($Name)) {
        $verb = if ($Enabled) { 'enable' } else { 'disable' }
        Write-Host "Usage: level-up $verb <name>" -ForegroundColor Yellow
        return
    }

    $config = Get-Config
    $entry  = @($config.commands) | Where-Object { $_.name -eq $Name }

    if ($null -eq $entry -or @($entry).Count -eq 0) {
        Write-Host "Not found: '$Name'" -ForegroundColor Red
        exit 1
    }

    $entry[0].enabled = $Enabled
    Save-Config $config

    if ($Enabled) {
        Write-Host "Enabled:  $Name" -ForegroundColor Green
    } else {
        Write-Host "Disabled: $Name" -ForegroundColor Red
    }
}

function Show-List {
    $config   = Get-Config
    $commands = @($config.commands)

    if ($commands.Count -eq 0) {
        Write-Host ""
        Write-Host "  No entries configured. Run 'level-up add' to add one." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    $maxName = ($commands | ForEach-Object { $_.name.Length } | Measure-Object -Maximum).Maximum
    $maxName = [Math]::Max($maxName, 4)  # minimum column width

    Write-Host ""
    Write-Host ("  Configured entries ({0}):" -f $commands.Count) -ForegroundColor Cyan
    Write-Host ""
    Write-Host ("  {0,-$maxName}  {1,-8}  {2}" -f "NAME", "STATUS", "COMMAND") -ForegroundColor White
    Write-Host ("  {0,-$maxName}  {1,-8}  {2}" -f ("-" * $maxName), "--------", ("-" * 40)) -ForegroundColor DarkGray

    foreach ($entry in $commands) {
        $isEnabled = $entry.enabled -ne $false
        $status    = if ($isEnabled) { 'enabled' } else { 'disabled' }
        $rowColor  = if ($isEnabled) { 'White' } else { 'DarkGray' }
        $statColor = if ($isEnabled) { 'Green' } else { 'Red' }
        $nameColor = if ($isEnabled) { 'Yellow' } else { 'DarkGray' }

        Write-Host ("  {0,-$maxName}  " -f $entry.name) -ForegroundColor $nameColor -NoNewline
        Write-Host ("{0,-8}  " -f $status) -ForegroundColor $statColor -NoNewline
        Write-Host ("{0}" -f $entry.command) -ForegroundColor $rowColor
    }
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------
function Open-Editor {
    Get-Config | Out-Null   # ensure file exists
    $editor = if ($env:EDITOR) { $env:EDITOR } else { 'notepad.exe' }
    Write-Host "Opening: $ConfigFile" -ForegroundColor DarkGray
    & $editor $ConfigFile
}

function Invoke-Doctor {
    $config   = Get-Config
    $commands = @($config.commands)

    if ($commands.Count -eq 0) {
        Write-Host "No entries configured." -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "  Checking tools..." -ForegroundColor Cyan
    Write-Host ""

    $allOk = $true
    $maxName = ($commands | ForEach-Object { $_.name.Length } | Measure-Object -Maximum).Maximum
    $maxName = [Math]::Max($maxName, 4)

    foreach ($entry in $commands) {
        $isEnabled = $entry.enabled -ne $false
        if (-not $isEnabled) {
            Write-Host ("  [DISABLED] {0,-$maxName}  (skipped)" -f $entry.name) -ForegroundColor DarkGray
            continue
        }
        $exe   = ($entry.command -split '\s+')[0]
        $found = Get-Command $exe -ErrorAction SilentlyContinue
        if ($found) {
            Write-Host ("  [OK]      {0,-$maxName}  {1}" -f $entry.name, $found.Source) -ForegroundColor Green
        } else {
            Write-Host ("  [MISSING] {0,-$maxName}  '$exe' not found in PATH" -f $entry.name) -ForegroundColor Red
            $allOk = $false
        }
    }
    Write-Host ""

    if (-not $allOk) { exit 1 }
}

function Show-LastLog {
    if (-not (Test-Path $LogDir)) {
        Write-Host "No logs found." -ForegroundColor Yellow
        return
    }
    $latest = Get-ChildItem -Path $LogDir -Filter '*.log' |
              Sort-Object LastWriteTime -Descending |
              Select-Object -First 1

    if ($null -eq $latest) {
        Write-Host "No logs found." -ForegroundColor Yellow
        return
    }

    Write-Host "Log: $($latest.FullName)" -ForegroundColor DarkGray
    Write-Host ""
    Get-Content -Path $latest.FullName
}

# ---------------------------------------------------------------------------
# Profile / alias management
# ---------------------------------------------------------------------------
function Get-ProfileText {
    if (Test-Path $PROFILE) {
        return Get-Content -Path $PROFILE -Raw -Encoding UTF8
    }
    return ""
}

function Install-ProfileAlias {
    param([switch]$Install, [string]$AddName)

    # Ensure profile directory exists
    $profileDir = Split-Path $PROFILE
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }

    # --install : add the main 'level-up' function
    if ($Install) {
        $marker  = '# >>> level-up'
        $current = Get-ProfileText

        if ($current -match [regex]::Escape($marker)) {
            Write-Host "level-up function already installed in:" -ForegroundColor Yellow
            Write-Host "  $PROFILE"
            Write-Host "Remove the '# >>> level-up ... # <<< level-up' block to reinstall."
            return
        }

        $scriptPath = $PSCommandPath
        $block = @"


# >>> level-up
function level-up { & "$scriptPath" @args }
# <<< level-up
"@
        Add-Content -Path $PROFILE -Value $block -Encoding UTF8
        Write-Host "Installed 'level-up' in:" -ForegroundColor Green
        Write-Host "  $PROFILE"
        Write-Host ""
        Write-Host "Reload your profile to activate:" -ForegroundColor DarkGray
        Write-Host "  . `$PROFILE" -ForegroundColor DarkGray
        return
    }

    # --add <name> : add a per-tool shortcut function
    if (-not [string]::IsNullOrEmpty($AddName)) {
        $config = Get-Config
        $entry  = @($config.commands) | Where-Object { $_.name -eq $AddName }

        if ($null -eq $entry -or @($entry).Count -eq 0) {
            Write-Host "No entry named '$AddName'. Add it first with 'level-up add'." -ForegroundColor Red
            exit 1
        }

        $funcName = "level-up-$AddName"
        $current  = Get-ProfileText

        if ($current -match "function $funcName") {
            Write-Host "Function '$funcName' already exists in $PROFILE" -ForegroundColor Yellow
            return
        }

        $scriptPath = $PSCommandPath
        $line       = "`nfunction $funcName { & `"$scriptPath`" run $AddName }"
        Add-Content -Path $PROFILE -Value $line -Encoding UTF8

        Write-Host "Added '$funcName' to:" -ForegroundColor Green
        Write-Host "  $PROFILE"
        Write-Host ""
        Write-Host "Reload your profile to activate:" -ForegroundColor DarkGray
        Write-Host "  . `$PROFILE" -ForegroundColor DarkGray
        return
    }

    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  level-up alias --install         Add 'level-up' function to profile"
    Write-Host "  level-up alias --add <name>      Add 'level-up-<name>' shortcut to profile"
}

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
function Show-Help {
    Write-Host @"

  level-up — bulk tool updater

  USAGE
    level-up <command> [args]

  COMMANDS
    list                      Show all configured entries
    add                       Interactively add a new entry
    remove <name>             Remove an entry by name
    enable <name>             Enable a disabled entry
    disable <name>            Disable an entry without removing it
    run <name> [name...]      Run one or more entries by name
    all                       Run every enabled entry
    edit                      Open config file in editor
    doctor                    Check all tools exist in PATH
    alias --install           Add 'level-up' function to PowerShell profile
    alias --add <name>        Add 'level-up-<name>' shortcut to profile
    log                       Show the most recent run log
    help                      Show this help

  PATHS
    Config : $ConfigFile
    Logs   : $LogDir

  EXAMPLES
    level-up add
    level-up list
    level-up run codex
    level-up run codex claude opencode
    level-up all
    level-up disable codex
    level-up enable codex
    level-up remove codex
    level-up doctor
    level-up alias --install
    level-up alias --add codex

  Built by Seyha Touch. Source: https://github.com/TouchSeyha

"@ -ForegroundColor White
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
switch ($Action.ToLower()) {
    'all'    { Invoke-AllCommands }
    'run'    { Invoke-NamedCommands -NameList $Names }
    'add'    { Add-Entry }
    'remove' {
        $target = if ($Names.Count -gt 0) { $Names[0] } else { "" }
        Remove-Entry -Name $target
    }
    'enable'  {
        $target = if ($Names.Count -gt 0) { $Names[0] } else { "" }
        Set-EntryEnabled -Name $target -Enabled $true
    }
    'disable' {
        $target = if ($Names.Count -gt 0) { $Names[0] } else { "" }
        Set-EntryEnabled -Name $target -Enabled $false
    }
    'list'   { Show-List }
    'edit'   { Open-Editor }
    'doctor' { Invoke-Doctor }
    'log'    { Show-LastLog }
    'alias'  {
        if ($Names -contains '--install') {
            Install-ProfileAlias -Install
        } elseif ($Names -contains '--add') {
            $idx = [array]::IndexOf([string[]]$Names, '--add')
            if ($idx -ge 0 -and ($idx + 1) -lt $Names.Count) {
                Install-ProfileAlias -AddName $Names[$idx + 1]
            } else {
                Write-Host "Usage: level-up alias --add <name>" -ForegroundColor Yellow
            }
        } else {
            Install-ProfileAlias
        }
    }
    'help'   { Show-Help }
    default  { Show-Help }
}
