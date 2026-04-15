param(
    [int]$MaxTurns = 50,
    [int]$SleepSeconds = 3,
    [string]$LastMessageFile = (Join-Path $env:TEMP "codex_last_msg.txt"),
    [string]$ResumePrompt,
    [string]$DonePattern = "(nothing (more|left)|all done|task complete|fully complete)",
    [string]$CompletionToken = "[TASK_COMPLETE]",
    [string]$ConfigPath = (Join-Path $HOME ".codex\config.toml"),
    [string]$SessionsDir = (Join-Path $HOME ".codex\sessions"),
    [string]$SessionId,
    [int]$SessionLimit = 30,
    [switch]$SkipConfigUpdate,
    [switch]$PatternOnly
)

$ErrorActionPreference = "Stop"

$script:Ui = ConvertFrom-Json @'
{
  "ResumePrompt": "\u7ee7\u7eed\u6267\u884c\u3002\u4e0d\u8981\u505c\u4e0b\u6765\u8be2\u95ee\u786e\u8ba4\uff0c\u4e5f\u4e0d\u8981\u53ea\u7ed9\u51fa\u5efa\u8bae\u3002\u76f4\u63a5\u6301\u7eed\u63a8\u8fdb\uff0c\u76f4\u5230\u5168\u90e8\u5b8c\u6210\u3002",
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

$script:CompletionInstruction = 'developer_instructions = "When the entire task is truly and fully complete with nothing left to do, end your final message with the exact token: [TASK_COMPLETE]. Do not use this token unless the task is genuinely finished."'
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

function Test-TaskCompletionSignal {
    param(
        [AllowEmptyString()][string]$Message,
        [string]$DonePattern,
        [string]$CompletionToken = "[TASK_COMPLETE]"
    )

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return $false
    }

    if ($CompletionToken -and $Message.Contains($CompletionToken)) {
        return $true
    }

    if ($DonePattern -and $Message -match $DonePattern) {
        return $true
    }

    return $false
}

function Get-CodexExecArgumentList {
    param(
        [Parameter(Mandatory = $true)][string]$LastMessageFile,
        [Parameter(Mandatory = $true)][string]$ResumePrompt,
        [string]$SessionId
    )

    $resumeArgs = if ($SessionId) {
        @("resume", $SessionId, $ResumePrompt)
    }
    else {
        @("resume", "--last", $ResumePrompt)
    }

    return @(
        "exec",
        "--yolo",
        "-o",
        $LastMessageFile
    ) + $resumeArgs
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
        Sort-Object LastWriteTime -Descending)

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
            $preview = "无用户消息 | $($payload.cwd)"
        }
        elseif ($preview -eq "(no preview)") {
            $preview = "无预览 | $sessionId"
        }

        [PSCustomObject]@{
            SessionId = $sessionId
            Timestamp = Get-SessionTimestampFromRolloutPath -Path $file.FullName
            Preview = $preview
            Path = $file.FullName
            LastWriteTime = $file.LastWriteTime
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

function Resolve-SessionId {
    param(
        [string]$SessionId,
        [string]$SessionsDir,
        [int]$SessionLimit = 30
    )

    if ($SessionId) {
        return $SessionId
    }

    $entries = @(Get-CodexSessionEntries -SessionsDir $SessionsDir -MaxCount $SessionLimit)
    $selected = Select-CodexSession -Entries $entries
    Write-Host ($script:Ui.ResumingSession -f $selected.SessionId) -ForegroundColor Green
    return $selected.SessionId
}

function Set-CodexDeveloperInstructions {
    param([Parameter(Mandatory = $true)][string]$ConfigPath)

    $content = if (Test-Path -LiteralPath $ConfigPath) {
        Get-Content -LiteralPath $ConfigPath -Raw
    }
    else {
        ""
    }

    if ($content -match [regex]::Escape($script:CompletionInstruction)) {
        return $false
    }

    $newContent = if ([string]::IsNullOrWhiteSpace($content)) {
        "$($script:CompletionInstruction)`r`n"
    }
    else {
        "$($script:CompletionInstruction)`r`n$content"
    }

    Set-Content -LiteralPath $ConfigPath -Value $newContent
    return $true
}

function Invoke-CodexAutopilot {
    param(
        [int]$MaxTurns = 50,
        [int]$SleepSeconds = 3,
        [Parameter(Mandatory = $true)][string]$LastMessageFile,
        [Parameter(Mandatory = $true)][string]$ResumePrompt,
        [string]$SessionId,
        [string]$DonePattern,
        [string]$CompletionToken = "[TASK_COMPLETE]"
    )

    $turn = 0
    while ($turn -lt $MaxTurns) {
        $turn += 1
        Write-Host ""
        Write-Host ("========== Turn {0} / {1} ==========" -f $turn, $MaxTurns) -ForegroundColor Cyan

        $args = Get-CodexExecArgumentList -LastMessageFile $LastMessageFile -ResumePrompt $ResumePrompt -SessionId $SessionId
        & codex @args
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0) {
            Write-Host ($script:Ui.ExecExitCode -f $exitCode) -ForegroundColor Yellow
            return $exitCode
        }

        $lastMessage = ""
        if (Test-Path -LiteralPath $LastMessageFile) {
            $lastMessage = Get-Content -LiteralPath $LastMessageFile -Raw
            Write-Host ""
            Write-Host $script:Ui.LastMessageHeader -ForegroundColor DarkCyan
            Write-Host $lastMessage.TrimEnd()
            Write-Host "----------------------------" -ForegroundColor DarkCyan
        }

        if (Test-TaskCompletionSignal -Message $lastMessage -DonePattern $DonePattern -CompletionToken $CompletionToken) {
            Write-Host ""
            Write-Host $script:Ui.TaskComplete -ForegroundColor Green
            return 0
        }

        Start-Sleep -Seconds $SleepSeconds
    }

    Write-Host ($script:Ui.MaxTurnsReached -f $MaxTurns) -ForegroundColor Yellow
    return 0
}

if ($env:CODEX_AUTOPILOT_IMPORT_ONLY -ne "1") {
    Initialize-ConsoleUtf8

    if (-not $PatternOnly -and -not $SkipConfigUpdate) {
        $updated = Set-CodexDeveloperInstructions -ConfigPath $ConfigPath
        if ($updated) {
            Write-Host ($script:Ui.ConfigUpdated -f $ConfigPath) -ForegroundColor Green
        }
        else {
            Write-Host ($script:Ui.ConfigAlreadyUpdated -f $ConfigPath) -ForegroundColor DarkGray
        }
    }

    $activeDonePattern = if ($PatternOnly) { $DonePattern } else { "" }
    $resolvedSessionId = Resolve-SessionId -SessionId $SessionId -SessionsDir $SessionsDir -SessionLimit $SessionLimit
    $exitCode = Invoke-CodexAutopilot -MaxTurns $MaxTurns -SleepSeconds $SleepSeconds -LastMessageFile $LastMessageFile -ResumePrompt $ResumePrompt -SessionId $resolvedSessionId -DonePattern $activeDonePattern -CompletionToken $(if ($PatternOnly) { "" } else { $CompletionToken })
    exit $exitCode
}
