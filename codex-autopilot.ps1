param(
    [int]$MaxTurns = 50,
    [int]$SleepSeconds = 3,
    [string]$LastMessageFile = (Join-Path $env:TEMP "codex_last_msg.txt"),
    [string]$LogFile = (Join-Path $PSScriptRoot "codex-autopilot.log"),
    [int]$TurnStallTimeoutSeconds = 1800,
    [int]$LastMessageStableSeconds = 30,
    [string]$ResumePrompt,
    [string]$SessionsDir = (Join-Path $HOME ".codex\sessions"),
    [string]$SessionId,
    [int]$SessionLimit = 30,
    [string]$RunStateFile,
    [ValidateSet("yolo", "full-auto", "sandbox")][string]$CodexExecutionMode = "yolo",
    [ValidateSet("read-only", "workspace-write", "danger-full-access")][string]$CodexSandboxMode = "workspace-write",
    [string]$CodexProfile
)

$ErrorActionPreference = "Stop"

$script:Ui = ConvertFrom-Json @'
{
  "ResumePrompt": "1.\u5148\u7528\u4e0a\u5e1d\u89c6\u89d2\u770b\u5f53\u524d\u72b6\u6001\u8ddd\u79bb\u6700\u7ec8\u9636\u6bb5\u7684\u6700\u7ec8\u76ee\u6807\u591a\u8fdc 2.\u63d0\u4ea4\u6240\u6709\u66f4\u6539\u4f5c\u4e3a\u65b0\u5f81\u7a0b\u7684\u57fa\u7ebf 3.\u7ee7\u7eed\u63a8\u8fdb\u65b0\u5f81\u7a0b,\u8981\u9ad8\u6548\u5229\u7528\u5b50\u4ee3\u7406\u52a0\u901f\u63a8\u8fdb\u901f\u5ea6",
  "ResumePromptShort": "\u7ee7\u7eed",
  "SelectPromptPrompt": "\u9009\u62e9\u63d0\u793a\u8bed: ",
  "NoPromptSelected": "\u672a\u9009\u62e9\u4efb\u4f55\u63d0\u793a\u8bed\u3002",
  "PromptHelp": "\u4f7f\u7528\u4e0a/\u4e0b\u65b9\u5411\u952e\u9009\u62e9\uff0c\u56de\u8f66\u786e\u8ba4\u3002",
  "PromptLabelDefault": "\u8be6\u7ec6\u63d0\u793a\u8bed",
  "PromptLabelShort": "\u7b80\u77ed\u63d0\u793a\u8bed\uff1a\u7ee7\u7eed",
  "NoSessionsFound": "\u672a\u627e\u5230 Codex \u4f1a\u8bdd\u3002",
  "NoSessionSelected": "\u672a\u9009\u62e9\u4efb\u4f55\u4f1a\u8bdd\u3002",
  "SelectSessionPrompt": "\u9009\u62e9\u4f1a\u8bdd: ",
  "RecentSessions": "\u6700\u8fd1\u7684\u4f1a\u8bdd\uff1a",
  "SelectSessionNumber": "\u8bf7\u8f93\u5165\u4f1a\u8bdd\u7f16\u53f7",
  "InvalidSelection": "\u8f93\u5165\u65e0\u6548\u3002",
  "ResumingSession": "\u7ee7\u7eed\u4f1a\u8bdd\uff1a{0}",
  "ConfigUpdated": "\u5df2\u66f4\u65b0 Codex \u914d\u7f6e\uff1a{0}",
  "ConfigAlreadyUpdated": "Codex \u914d\u7f6e\u5df2\u5305\u542b\u5b8c\u6210\u6807\u8bb0\u6307\u4ee4\uff1a{0}",
  "ExecExitCode": "codex exec \u4ee5\u9000\u51fa\u7801 {0} \u7ed3\u675f\uff0c\u505c\u6b62\u6267\u884c\u3002",
  "LastMessageHeader": "--- \u6a21\u578b\u7684\u6700\u540e\u6d88\u606f ---",
  "TaskComplete": "\u4efb\u52a1\u5df2\u5168\u90e8\u5b8c\u6210\uff0c\u9000\u51fa\u3002",
  "MaxTurnsReached": "\u5df2\u8fbe\u5230\u6700\u5927\u8f6e\u6b21 ({0})\uff0c\u505c\u6b62\u6267\u884c\u4ee5\u907f\u514d\u5931\u63a7\u3002"
}
'@

if (-not $PSBoundParameters.ContainsKey("ResumePrompt")) {
    $ResumePrompt = $script:Ui.ResumePrompt
}

$script:Utf8Encoding = New-Object System.Text.UTF8Encoding($false)

function Initialize-ConsoleUtf8 {
    [Console]::InputEncoding = $script:Utf8Encoding
    [Console]::OutputEncoding = $script:Utf8Encoding
    $global:OutputEncoding = $script:Utf8Encoding
    try {
        cmd /c chcp 65001 > $null
    }
    catch {}
}

function New-SharedUtf8Reader {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fileStream = New-Object System.IO.FileStream(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite
    )

    return New-Object System.IO.StreamReader($fileStream, $script:Utf8Encoding, $true)
}

function Read-TextFileUtf8 {
    param([Parameter(Mandatory = $true)][string]$Path)

    $reader = New-SharedUtf8Reader -Path $Path
    try {
        return $reader.ReadToEnd()
    }
    finally {
        $reader.Dispose()
    }
}

function Write-AutopilotLog {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $directory = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $line = "{0} {1}" -f ([DateTimeOffset]::Now.ToString("o")), $Message
    [System.IO.File]::AppendAllText($Path, $line + [Environment]::NewLine, $script:Utf8Encoding)
}

function Get-TextSha256 {
    param([AllowNull()][string]$Text)

    if ($null -eq $Text) {
        $Text = ""
    }

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $script:Utf8Encoding.GetBytes($Text)
        $hashBytes = $sha256.ComputeHash($bytes)
        return (($hashBytes | ForEach-Object { $_.ToString("x2") }) -join "")
    }
    finally {
        $sha256.Dispose()
    }
}

function Write-AutopilotRunState {
    param(
        [string]$Path,
        [int]$Turn,
        [int]$MaxTurns,
        [int]$LastExitCode,
        [string]$StopReason = "",
        [string]$SessionId,
        [string]$WorkingDirectory,
        [string]$LastMessage = "",
        [bool]$StallRecovered = $false
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    $directory = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    if ($null -eq $LastMessage) {
        $LastMessage = ""
    }

    $state = [ordered]@{
        updated_at = [DateTimeOffset]::Now.ToString("o")
        session_id = $(if ($SessionId) { $SessionId } else { "" })
        working_directory = $(if ($WorkingDirectory) { $WorkingDirectory } else { "" })
        turn = $Turn
        max_turns = $MaxTurns
        last_exit_code = $LastExitCode
        stop_reason = $StopReason
        stall_recovered = $StallRecovered
        last_message_length = $LastMessage.Length
        last_message_sha256 = Get-TextSha256 -Text $LastMessage
    }

    $json = $state | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, $script:Utf8Encoding)
}

function Invoke-FzfSelection {
    param(
        [Parameter(Mandatory = $true)][string]$CommandSource,
        [Parameter(Mandatory = $true)][string[]]$Options,
        [Parameter(Mandatory = $true)][string]$Prompt,
        [int]$Height = 20
    )

    return $Options | & $CommandSource --prompt $Prompt --height $Height --reverse
}

function Get-ConsoleKeyInfo {
    return $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Write-MenuOptions {
    param(
        [Parameter(Mandatory = $true)][object[]]$Entries,
        [Parameter(Mandatory = $true)][int]$SelectedIndex,
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][string]$HelpText
    )

    Clear-Host
    Write-Host $Prompt -ForegroundColor Cyan
    Write-Host $HelpText -ForegroundColor DarkGray

    for ($i = 0; $i -lt $Entries.Count; $i++) {
        $prefix = if ($i -eq $SelectedIndex) { "> " } else { "  " }
        Write-Host ($prefix + $Entries[$i].Label)
    }

    $selectedEntry = $Entries[$SelectedIndex]
    if ($selectedEntry.PSObject.Properties.Name -contains "Value" -and -not [string]::IsNullOrWhiteSpace($selectedEntry.Value)) {
        Write-Host ""
        Write-Host ("-" * 60) -ForegroundColor DarkGray
        Write-Host $selectedEntry.Value
    }
}

function Get-TurnBanner {
    param(
        [Parameter(Mandatory = $true)][int]$Turn,
        [Parameter(Mandatory = $true)][int]$MaxTurns,
        [ValidateSet("Begin", "End")][string]$Phase = "Begin"
    )
    $label = if ($Phase -eq "End") { [string]::Concat([char]0x7ED3, [char]0x675F) } else { [string]::Concat([char]0x5F00, [char]0x59CB) }
    return ("========== Turn {0} / {1} {2} ==========" -f $Turn, $MaxTurns, $label)
}

function Get-WindowTitle {
    param(
        [ValidateSet("Idle", "Running", "Completed", "Failed")][string]$Phase = "Idle",
        [int]$Turn,
        [int]$MaxTurns,
        [int]$ExitCode
    )

    switch ($Phase) {
        "Running" {
            return ("codex-autopilot | Turn {0}/{1}" -f $Turn, $MaxTurns)
        }
        "Completed" {
            return ("codex-autopilot | {0}" -f ([string]::Concat([char]0x5DF2, [char]0x5B8C, [char]0x6210)))
        }
        "Failed" {
            return ("codex-autopilot | {0}({1})" -f ([string]::Concat([char]0x5931, [char]0x8D25)), $ExitCode)
        }
        default {
            return "codex-autopilot"
        }
    }
}

function Set-WindowTitle {
    param([Parameter(Mandatory = $true)][string]$Title)

    try {
        $host.UI.RawUI.WindowTitle = $Title
    }
    catch {}
}

function Start-WindowTitleKeeper {
    param(
        [AllowEmptyString()][string]$Title,
        [int]$IntervalMilliseconds = 500
    )

    if ([string]::IsNullOrWhiteSpace($Title)) {
        return $null
    }

    if (-not ("CodexAutopilot.WindowTitleKeeper" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;

namespace CodexAutopilot {
    public sealed class WindowTitleKeeper : IDisposable {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        private static extern bool SetConsoleTitle(string lpConsoleTitle);

        private readonly CancellationTokenSource _cancellation = new CancellationTokenSource();
        private readonly Task _task;

        public WindowTitleKeeper(string title, int intervalMilliseconds) {
            _task = Task.Run(() => {
                while (!_cancellation.IsCancellationRequested) {
                    try {
                        SetConsoleTitle(title);
                    }
                    catch {
                    }

                    try {
                        Task.Delay(intervalMilliseconds, _cancellation.Token).Wait();
                    }
                    catch {
                    }
                }
            }, _cancellation.Token);
        }

        public void Dispose() {
            _cancellation.Cancel();
            try {
                _task.Wait(200);
            }
            catch {
            }
            _cancellation.Dispose();
        }
    }
}
"@
    }

    return [CodexAutopilot.WindowTitleKeeper]::new($Title, $IntervalMilliseconds)
}

function Stop-WindowTitleKeeper {
    param($Keeper)

    if ($null -eq $Keeper) {
        return
    }

    try {
        $Keeper.Dispose()
    }
    catch {}
}

function Get-CodexExecArgumentList {
    param(
        [Parameter(Mandatory = $true)][string]$LastMessageFile,
        [string]$ResumePrompt,
        [string]$SessionId,
        [ValidateSet("yolo", "full-auto", "sandbox")][string]$CodexExecutionMode = "yolo",
        [ValidateSet("read-only", "workspace-write", "danger-full-access")][string]$CodexSandboxMode = "workspace-write",
        [string]$CodexProfile
    )

    $resumeArgs = if ($SessionId) {
        @("resume", $SessionId, $ResumePrompt)
    }
    else {
        @("resume", "--last", $ResumePrompt)
    }

    $args = @("exec")

    if (-not [string]::IsNullOrWhiteSpace($CodexProfile)) {
        $args += @("--profile", $CodexProfile)
    }

    switch ($CodexExecutionMode) {
        "full-auto" {
            $args += "--full-auto"
        }
        "sandbox" {
            $args += @("--sandbox", $CodexSandboxMode)
        }
        default {
            $args += "--yolo"
        }
    }

    return $args + @("-o", $LastMessageFile) + $resumeArgs
}

function Select-ResumePrompt {
    $entries = @(
        [PSCustomObject]@{
            Key = "Default"
            Label = $script:Ui.PromptLabelDefault
            Value = $script:Ui.ResumePrompt
        }
        [PSCustomObject]@{
            Key = "Short"
            Label = $script:Ui.PromptLabelShort
            Value = $script:Ui.ResumePromptShort
        }
    )

    $selectedIndex = 0
    Write-MenuOptions -Entries $entries -SelectedIndex $selectedIndex -Prompt $script:Ui.SelectPromptPrompt -HelpText $script:Ui.PromptHelp

    while ($true) {
        $keyInfo = Get-ConsoleKeyInfo
        switch ($keyInfo.VirtualKeyCode) {
            38 {
                $selectedIndex = ($selectedIndex - 1 + $entries.Count) % $entries.Count
                Write-MenuOptions -Entries $entries -SelectedIndex $selectedIndex -Prompt $script:Ui.SelectPromptPrompt -HelpText $script:Ui.PromptHelp
            }
            40 {
                $selectedIndex = ($selectedIndex + 1) % $entries.Count
                Write-MenuOptions -Entries $entries -SelectedIndex $selectedIndex -Prompt $script:Ui.SelectPromptPrompt -HelpText $script:Ui.PromptHelp
            }
            13 {
                return $entries[$selectedIndex].Value
            }
            27 {
                throw $script:Ui.NoPromptSelected
            }
        }
    }
}

function Invoke-CodexCommand {
    param(
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [string]$WindowTitle,
        [int]$TurnStallTimeoutSeconds = 0,
        [string]$LastMessageFile,
        [int]$LastMessageStableSeconds = 30,
        [string]$LogFile,
        [int]$Turn = 0
    )

    $keeper = if ([string]::IsNullOrWhiteSpace($WindowTitle)) {
        $null
    }
    else {
        Start-WindowTitleKeeper -Title $WindowTitle
    }
    try {
        if ($TurnStallTimeoutSeconds -gt 0 -and -not [string]::IsNullOrWhiteSpace($LastMessageFile) -and -not [string]::IsNullOrWhiteSpace($LogFile) -and $Turn -gt 0) {
            $process = Start-CodexProcess -FilePath (Get-CodexExecutablePath) -ArgumentList $ArgumentList
            return Wait-ForCodexProcessExit -Process $process -Turn $Turn -LastMessageFile $LastMessageFile -TurnStallTimeoutSeconds $TurnStallTimeoutSeconds -LastMessageStableSeconds $LastMessageStableSeconds -LogFile $LogFile
        }
        return [int](Invoke-CodexExecutable -ArgumentList $ArgumentList)
    }
    finally {
        Stop-WindowTitleKeeper -Keeper $keeper
    }
}

function Get-CodexExecutablePath {
    $preferredExePath = Join-Path $env:APPDATA "npm\node_modules\@openai\codex\node_modules\@openai\codex-win32-x64\vendor\x86_64-pc-windows-msvc\codex\codex.exe"
    if (Test-Path -LiteralPath $preferredExePath) {
        return $preferredExePath
    }

    $preferredWrapperPath = Join-Path $env:APPDATA "npm\codex.ps1"
    if (Test-Path -LiteralPath $preferredWrapperPath) {
        return $preferredWrapperPath
    }

    $command = Get-Command codex -ErrorAction Stop
    return $command.Source
}

function Invoke-CodexExecutable {
    param([Parameter(Mandatory = $true)][string[]]$ArgumentList)

    $codexExecutable = Get-CodexExecutablePath
    if ($codexExecutable.EndsWith(".ps1", [System.StringComparison]::OrdinalIgnoreCase)) {
        $wrapperArgs = @(
            "-NoLogo",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            $codexExecutable
        ) + $ArgumentList
        $process = Start-CodexProcess -FilePath (Join-Path $PSHOME "powershell.exe") -ArgumentList $wrapperArgs
        $process.WaitForExit()
        return [int]$process.ExitCode
    }

    $process = Start-CodexProcess -FilePath $codexExecutable -ArgumentList $ArgumentList
    $process.WaitForExit()
    return [int]$process.ExitCode
}

function ConvertTo-ProcessArgumentString {
    param([Parameter(Mandatory = $true)][string[]]$ArgumentList)

    $escapedArguments = foreach ($argument in $ArgumentList) {
        if ($null -eq $argument) {
            '""'
            continue
        }

        if ($argument -notmatch '[\s"]') {
            $argument
            continue
        }

        $escaped = $argument -replace '(\\*)"', '$1$1\"'
        $escaped = $escaped -replace '(\\+)$', '$1$1'
        '"{0}"' -f $escaped
    }

    return ($escapedArguments -join ' ')
}

function Start-CodexProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.CreateNoWindow = $false
    if ($startInfo.PSObject.Properties.Name -contains 'ArgumentList' -and $null -ne $startInfo.ArgumentList) {
        foreach ($argument in $ArgumentList) {
            [void]$startInfo.ArgumentList.Add($argument)
        }
    }
    elseif ($startInfo.PSObject.Properties.Name -contains 'Arguments') {
        $startInfo.Arguments = ConvertTo-ProcessArgumentString -ArgumentList $ArgumentList
    }
    else {
        throw "ProcessStartInfo does not expose ArgumentList or Arguments."
    }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw ("Failed to start process: {0}" -f $FilePath)
    }

    if ($null -ne $process.StandardInput) {
        $process.StandardInput.Close()
    }

    return $process
}

function Stop-ProcessTree {
    param([Parameter(Mandatory = $true)][int]$ProcessId)

    $children = Get-CimInstance Win32_Process -Filter ("ParentProcessId = {0}" -f $ProcessId) -ErrorAction SilentlyContinue
    foreach ($child in @($children)) {
        Stop-ProcessTree -ProcessId $child.ProcessId
    }

    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}

function Test-CodexTurnStalled {
    param(
        [Parameter(Mandatory = $true)][datetime]$TurnStartTime,
        [Parameter(Mandatory = $true)][string]$LastMessageFile,
        [Parameter(Mandatory = $true)][int]$TurnStallTimeoutSeconds,
        [Parameter(Mandatory = $true)][int]$LastMessageStableSeconds
    )

    if ($TurnStallTimeoutSeconds -le 0) {
        return $false
    }

    try {
        $item = Get-Item -LiteralPath $LastMessageFile -ErrorAction Stop
    }
    catch {
        return $false
    }

    if ($item.Length -le 0) {
        return $false
    }

    $now = Get-Date
    $elapsedSeconds = (New-TimeSpan -Start $TurnStartTime -End $now).TotalSeconds
    if ($elapsedSeconds -lt $TurnStallTimeoutSeconds) {
        return $false
    }

    $stableSeconds = (New-TimeSpan -Start $item.LastWriteTime -End $now).TotalSeconds
    return ($stableSeconds -ge $LastMessageStableSeconds)
}

function Wait-ForCodexProcessExit {
    param(
        [Parameter(Mandatory = $true)]$Process,
        [Parameter(Mandatory = $true)][int]$Turn,
        [Parameter(Mandatory = $true)][string]$LastMessageFile,
        [Parameter(Mandatory = $true)][int]$TurnStallTimeoutSeconds,
        [Parameter(Mandatory = $true)][int]$LastMessageStableSeconds,
        [Parameter(Mandatory = $true)][string]$LogFile
    )

    $turnStartTime = Get-Date
    while (-not $Process.WaitForExit(1000)) {
        if (Test-CodexTurnStalled -TurnStartTime $turnStartTime -LastMessageFile $LastMessageFile -TurnStallTimeoutSeconds $TurnStallTimeoutSeconds -LastMessageStableSeconds $LastMessageStableSeconds) {
            Write-AutopilotLog -Path $LogFile -Message ("event=turn_stall_detected turn={0} timeout_seconds={1}" -f $Turn, $TurnStallTimeoutSeconds)
            Stop-ProcessTree -ProcessId $Process.Id
            [void]$Process.WaitForExit(5000)
            if (-not $Process.HasExited) {
                Write-AutopilotLog -Path $LogFile -Message ("event=stop reason=turn_stall_unrecoverable turn={0}" -f $Turn)
                throw ("Unable to recover stalled codex process for turn {0}" -f $Turn)
            }

            Write-AutopilotLog -Path $LogFile -Message ("event=turn_stall_recovered turn={0}" -f $Turn)
            return [PSCustomObject]@{
                ExitCode = 0
                StallRecovered = $true
            }
        }
    }

    return [PSCustomObject]@{
        ExitCode = [int]$Process.ExitCode
        StallRecovered = $false
    }
}

function Get-SessionIdFromRolloutPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    if ([string]::IsNullOrWhiteSpace($fileName) -or $fileName.Length -lt 37) {
        return $null
    }

    $candidate = $fileName.Substring($fileName.Length - 36)
    if ($fileName.Substring(0, $fileName.Length - 36) -notmatch '-$') {
        return $null
    }

    $parsed = [guid]::Empty
    if (-not [guid]::TryParse($candidate, [ref]$parsed)) {
        return $null
    }

    return $candidate
}

function Get-SessionTimestampFromRolloutPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $sessionId = Get-SessionIdFromRolloutPath -Path $Path
    if (-not $sessionId) {
        return $null
    }

    $prefixLength = "rollout-".Length
    $timestampLength = $fileName.Length - $prefixLength - 1 - $sessionId.Length
    if ($timestampLength -le 0) {
        return $null
    }

    return $fileName.Substring($prefixLength, $timestampLength)
}

function Get-SessionMetaPayloadFromRollout {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        $reader = New-SharedUtf8Reader -Path $Path
        try {
            $firstLine = $reader.ReadLine()
        }
        finally {
            $reader.Dispose()
        }
    }
    catch {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($firstLine)) {
        return $null
    }

    try {
        $item = $firstLine | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return $null
    }

    if ($item.type -ne "session_meta") {
        return $null
    }

    return $item.payload
}

function Get-SessionPreviewFromRollout {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$MaxLength = 80
    )

    $fallbackMessage = $null

    try {
        $reader = New-SharedUtf8Reader -Path $Path
        try {
            while (($line = $reader.ReadLine()) -ne $null) {
                if ([string]::IsNullOrWhiteSpace($line)) {
                    continue
                }

                try {
                    $item = $line | ConvertFrom-Json -ErrorAction Stop
                }
                catch {
                    continue
                }

                $message = $null
                if ($item.type -eq "event_msg" -and $item.payload.type -eq "user_message") {
                    $message = $item.payload.message
                }

                if (-not $message -and -not $fallbackMessage -and $item.payload.type -eq "message" -and $item.payload.role -eq "user") {
                    foreach ($contentItem in @($item.payload.content)) {
                        if ($contentItem.type -eq "input_text" -and $contentItem.text) {
                            $fallbackMessage = $contentItem.text
                            break
                        }
                    }
                }

                if (-not [string]::IsNullOrWhiteSpace($message)) {
                    $normalized = ($message -replace '\s+', ' ').Trim()
                    if ($normalized.Length -gt $MaxLength) {
                        return $normalized.Substring(0, $MaxLength)
                    }

                    return $normalized
                }
            }
        }
        finally {
            $reader.Dispose()
        }
    }
    catch {
        return "(no preview)"
    }

    if (-not [string]::IsNullOrWhiteSpace($fallbackMessage)) {
        $normalized = ($fallbackMessage -replace '\s+', ' ').Trim()
        if ($normalized.Length -gt $MaxLength) {
            return $normalized.Substring(0, $MaxLength)
        }

        return $normalized
    }

    return "(no preview)"
}

function Test-IsPrimarySessionRollout {
    param([Parameter(Mandatory = $true)][string]$Path)

    $payload = Get-SessionMetaPayloadFromRollout -Path $Path
    if ($null -eq $payload) {
        return $true
    }

    if ($null -ne $payload.source.subagent) {
        return $false
    }

    $role = [string]$payload.agent_role
    if ([string]::IsNullOrWhiteSpace($role) -or $role -eq "default") {
        return $true
    }

    return $false
}

function Get-CodexSessionEntries {
    param(
        [Parameter(Mandatory = $true)][string]$SessionsDir,
        [int]$MaxCount = 30
    )

    if (-not (Test-Path -LiteralPath $SessionsDir)) {
        return @()
    }

    $files = @(Get-ChildItem -LiteralPath $SessionsDir -Recurse -File -Filter "rollout-*.jsonl" |
        Sort-Object `
            @{ Expression = { Get-SessionTimestampFromRolloutPath -Path $_.FullName }; Descending = $true }, `
            @{ Expression = { $_.Name }; Descending = $true }, `
            @{ Expression = { $_.LastWriteTime }; Descending = $true })

    $entries = foreach ($file in $files) {
        if (-not (Test-IsPrimarySessionRollout -Path $file.FullName)) {
            continue
        }

        $sessionId = Get-SessionIdFromRolloutPath -Path $file.FullName
        if (-not $sessionId) {
            continue
        }

        $payload = Get-SessionMetaPayloadFromRollout -Path $file.FullName
        $preview = Get-SessionPreviewFromRollout -Path $file.FullName
        if ($preview -eq "(no preview)" -and $payload -and $payload.cwd) {
            $preview = "No user message | $($payload.cwd)"
        }
        elseif ($preview -eq "(no preview)") {
            $preview = "No preview | $sessionId"
        }

        [PSCustomObject]@{
            SessionId = $sessionId
            Timestamp = Get-SessionTimestampFromRolloutPath -Path $file.FullName
            Preview = $preview
            Path = $file.FullName
            LastWriteTime = $file.LastWriteTime
            WorkingDirectory = if ($payload -and $payload.cwd) { $payload.cwd } else { $null }
        }
    }

    return @($entries | Select-Object -First $MaxCount)
}

function Select-CodexSession {
    param(
        [Parameter(Mandatory = $true)][object[]]$Entries
    )

    if (-not $Entries -or $Entries.Count -eq 0) {
        throw $script:Ui.NoSessionsFound
    }

    $fzfCommand = Get-Command fzf -ErrorAction SilentlyContinue
    if ($fzfCommand) {
        $options = $Entries | ForEach-Object {
            "{0}`t[{1}]`t{2}" -f $_.SessionId, $_.Timestamp, $_.Preview
        }

        $selected = $options | & $fzfCommand.Source --prompt $script:Ui.SelectSessionPrompt --height 20 --reverse
        if ([string]::IsNullOrWhiteSpace($selected)) {
            throw $script:Ui.NoSessionSelected
        }

        $selectedId = ($selected -split "`t", 2)[0]
        return ($Entries | Where-Object { $_.SessionId -eq $selectedId } | Select-Object -First 1)
    }

    Write-Host $script:Ui.RecentSessions -ForegroundColor Cyan
    for ($i = 0; $i -lt $Entries.Count; $i++) {
        $entry = $Entries[$i]
        Write-Host ("[{0}] {1} [{2}] {3}" -f ($i + 1), $entry.SessionId, $entry.Timestamp, $entry.Preview)
    }

    while ($true) {
        $choice = Read-Host $script:Ui.SelectSessionNumber
        $index = 0
        if ([int]::TryParse($choice, [ref]$index) -and $index -ge 1 -and $index -le $Entries.Count) {
            return $Entries[$index - 1]
        }

        Write-Host $script:Ui.InvalidSelection -ForegroundColor Yellow
    }
}

function Resolve-SessionContext {
    param(
        [string]$SessionId,
        [string]$SessionsDir,
        [int]$SessionLimit = 30
    )

    if ($SessionId) {
        $entry = Get-CodexSessionEntries -SessionsDir $SessionsDir -MaxCount ([int]::MaxValue) |
            Where-Object { $_.SessionId -eq $SessionId } |
            Select-Object -First 1

        return [PSCustomObject]@{
            SessionId = $SessionId
            WorkingDirectory = if ($entry) { $entry.WorkingDirectory } else { $null }
        }
    }

    $entries = @(Get-CodexSessionEntries -SessionsDir $SessionsDir -MaxCount $SessionLimit)
    $selected = Select-CodexSession -Entries $entries
    Write-Host ($script:Ui.ResumingSession -f $selected.SessionId) -ForegroundColor Green
    return [PSCustomObject]@{
        SessionId = $selected.SessionId
        WorkingDirectory = $selected.WorkingDirectory
    }
}

function Invoke-CodexAutopilot {
    param(
        [int]$MaxTurns = 50,
        [int]$SleepSeconds = 3,
        [Parameter(Mandatory = $true)][string]$LastMessageFile,
        [string]$LogFile = (Join-Path $PSScriptRoot "codex-autopilot.log"),
        [int]$TurnStallTimeoutSeconds = 1800,
        [int]$LastMessageStableSeconds = 30,
        [Parameter(Mandatory = $true)][string]$ResumePrompt,
        [string]$SessionId,
        [string]$WorkingDirectory,
        [string]$RunStateFile,
        [ValidateSet("yolo", "full-auto", "sandbox")][string]$CodexExecutionMode = "yolo",
        [ValidateSet("read-only", "workspace-write", "danger-full-access")][string]$CodexSandboxMode = "workspace-write",
        [string]$CodexProfile
    )

    $turn = 0
    while ($turn -lt $MaxTurns) {
        $turn += 1
        Write-AutopilotLog -Path $LogFile -Message ("event=turn_start turn={0} max_turns={1} session_id={2} working_directory={3}" -f $turn, $MaxTurns, $(if ($SessionId) { $SessionId } else { "-" }), $(if ($WorkingDirectory) { $WorkingDirectory } else { "-" }))
        Set-WindowTitle -Title (Get-WindowTitle -Phase "Running" -Turn $turn -MaxTurns $MaxTurns)
        Write-Host ""
        Write-Host (Get-TurnBanner -Turn $turn -MaxTurns $MaxTurns -Phase "Begin") -ForegroundColor Cyan

        $args = Get-CodexExecArgumentList -LastMessageFile $LastMessageFile -ResumePrompt $ResumePrompt -SessionId $SessionId -CodexExecutionMode $CodexExecutionMode -CodexSandboxMode $CodexSandboxMode -CodexProfile $CodexProfile
        Write-AutopilotLog -Path $LogFile -Message ("event=exec_invoke turn={0} command={1}" -f $turn, ((Get-CodexExecutablePath), ($args -join ' ') -join ' '))
        $runningTitle = Get-WindowTitle -Phase "Running" -Turn $turn -MaxTurns $MaxTurns
        if ($WorkingDirectory) {
            Push-Location -LiteralPath $WorkingDirectory
            try {
                try {
                    $commandResult = Invoke-CodexCommand -ArgumentList $args -WindowTitle $runningTitle -TurnStallTimeoutSeconds $TurnStallTimeoutSeconds -LastMessageFile $LastMessageFile -LastMessageStableSeconds $LastMessageStableSeconds -LogFile $LogFile -Turn $turn
                }
                catch {
                    Write-AutopilotLog -Path $LogFile -Message ("event=exec_exception turn={0} message={1}" -f $turn, $_.Exception.Message)
                    throw
                }
            }
            finally {
                Pop-Location
            }
        }
        else {
            try {
                $commandResult = Invoke-CodexCommand -ArgumentList $args -WindowTitle $runningTitle -TurnStallTimeoutSeconds $TurnStallTimeoutSeconds -LastMessageFile $LastMessageFile -LastMessageStableSeconds $LastMessageStableSeconds -LogFile $LogFile -Turn $turn
            }
            catch {
                Write-AutopilotLog -Path $LogFile -Message ("event=exec_exception turn={0} message={1}" -f $turn, $_.Exception.Message)
                throw
            }
        }

        if ($commandResult -is [int]) {
            $exitCode = [int]$commandResult
            $stallRecovered = $false
        }
        elseif ($null -ne $commandResult -and $commandResult.PSObject.Properties.Name -contains "ExitCode") {
            $exitCode = [int]$commandResult.ExitCode
            $stallRecovered = ($commandResult.PSObject.Properties.Name -contains "StallRecovered" -and [bool]$commandResult.StallRecovered)
        }
        else {
            throw "Invoke-CodexCommand returned an unsupported result."
        }

        Write-AutopilotLog -Path $LogFile -Message ("event=exec_exit turn={0} exit_code={1}" -f $turn, $exitCode)

        if ($exitCode -ne 0) {
            Set-WindowTitle -Title (Get-WindowTitle -Phase "Failed" -ExitCode $exitCode)
            Write-AutopilotLog -Path $LogFile -Message ("event=stop reason=exec_exit_nonzero turn={0} exit_code={1}" -f $turn, $exitCode)
            Write-AutopilotRunState -Path $RunStateFile -Turn $turn -MaxTurns $MaxTurns -LastExitCode $exitCode -StopReason "exec_exit_nonzero" -SessionId $SessionId -WorkingDirectory $WorkingDirectory -LastMessage "" -StallRecovered $stallRecovered
            Write-Host ($script:Ui.ExecExitCode -f $exitCode) -ForegroundColor Yellow
            return $exitCode
        }

        $lastMessage = ""
        if (Test-Path -LiteralPath $LastMessageFile) {
            $lastMessage = Read-TextFileUtf8 -Path $LastMessageFile
            Write-AutopilotLog -Path $LogFile -Message ("event=last_message_read turn={0} length={1}" -f $turn, $lastMessage.Length)
            Write-Host ""
            Write-Host $script:Ui.LastMessageHeader -ForegroundColor DarkCyan
            Write-Host $lastMessage.TrimEnd()
            Write-Host "----------------------------" -ForegroundColor DarkCyan
        }

        Write-Host (Get-TurnBanner -Turn $turn -MaxTurns $MaxTurns -Phase "End") -ForegroundColor DarkCyan
        Write-AutopilotLog -Path $LogFile -Message ("event=turn_end turn={0} exit_code={1}" -f $turn, $exitCode)
        Write-AutopilotRunState -Path $RunStateFile -Turn $turn -MaxTurns $MaxTurns -LastExitCode $exitCode -StopReason $(if ($turn -lt $MaxTurns) { "loop_continue" } else { "" }) -SessionId $SessionId -WorkingDirectory $WorkingDirectory -LastMessage $lastMessage -StallRecovered $stallRecovered

        Write-AutopilotLog -Path $LogFile -Message ("event=sleep_start turn={0} seconds={1}" -f $turn, $SleepSeconds)
        Start-Sleep -Seconds $SleepSeconds
        Write-AutopilotLog -Path $LogFile -Message ("event=sleep_end turn={0}" -f $turn)
        if ($turn -lt $MaxTurns) {
            Write-AutopilotLog -Path $LogFile -Message ("event=loop_continue next_turn={0}" -f ($turn + 1))
        }
    }

    Set-WindowTitle -Title (Get-WindowTitle -Phase "Completed")
    Write-AutopilotLog -Path $LogFile -Message ("event=stop reason=max_turns_reached turn={0} exit_code=0" -f $turn)
    Write-AutopilotRunState -Path $RunStateFile -Turn $turn -MaxTurns $MaxTurns -LastExitCode 0 -StopReason "max_turns_reached" -SessionId $SessionId -WorkingDirectory $WorkingDirectory -LastMessage $lastMessage -StallRecovered $stallRecovered
    Write-Host ($script:Ui.MaxTurnsReached -f $MaxTurns) -ForegroundColor Yellow
    return 0
}

if ($env:CODEX_AUTOPILOT_IMPORT_ONLY -ne "1") {
    Initialize-ConsoleUtf8
    $sessionContext = Resolve-SessionContext -SessionId $SessionId -SessionsDir $SessionsDir -SessionLimit $SessionLimit
    if (-not $PSBoundParameters.ContainsKey("ResumePrompt")) {
        $ResumePrompt = Select-ResumePrompt
    }
    $exitCode = Invoke-CodexAutopilot -MaxTurns $MaxTurns -SleepSeconds $SleepSeconds -LastMessageFile $LastMessageFile -LogFile $LogFile -TurnStallTimeoutSeconds $TurnStallTimeoutSeconds -LastMessageStableSeconds $LastMessageStableSeconds -ResumePrompt $ResumePrompt -SessionId $sessionContext.SessionId -WorkingDirectory $sessionContext.WorkingDirectory -RunStateFile $RunStateFile -CodexExecutionMode $CodexExecutionMode -CodexSandboxMode $CodexSandboxMode -CodexProfile $CodexProfile
    exit $exitCode
}
