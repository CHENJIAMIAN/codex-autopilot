$env:CODEX_AUTOPILOT_IMPORT_ONLY = "1"
. "D:\Desktop\codex-autopilot\codex-autopilot.ps1"
Remove-Item Env:CODEX_AUTOPILOT_IMPORT_ONLY -ErrorAction SilentlyContinue

$expectedUi = ConvertFrom-Json @'
{
  "ResumePrompt": "1.\u5148\u7528\u4e0a\u5e1d\u89c6\u89d2\u770b\u5f53\u524d\u72b6\u6001\u8ddd\u79bb\u6700\u7ec8\u9636\u6bb5\u7684\u6700\u7ec8\u76ee\u6807\u591a\u8fdc 2.\u63d0\u4ea4\u6240\u6709\u66f4\u6539\u4f5c\u4e3a\u65b0\u5f81\u7a0b\u7684\u57fa\u7ebf 3.\u7ee7\u7eed\u63a8\u8fdb\u65b0\u5f81\u7a0b,\u8981\u9ad8\u6548\u5229\u7528\u5b50\u4ee3\u7406\u52a0\u901f\u63a8\u8fdb\u901f\u5ea6",
  "ResumePromptShort": "\u7ee7\u7eed",
  "SelectPromptPrompt": "\u9009\u62e9\u63d0\u793a\u8bed: ",
  "NoPromptSelected": "\u672a\u9009\u62e9\u4efb\u4f55\u63d0\u793a\u8bed\u3002",
  "PromptHelp": "\u4f7f\u7528\u4e0a/\u4e0b\u65b9\u5411\u952e\u9009\u62e9\uff0c\u56de\u8f66\u786e\u8ba4\u3002",
  "PromptLabelDefault": "\u8be6\u7ec6\u63d0\u793a\u8bed",
  "PromptLabelShort": "\u7b80\u77ed\u63d0\u793a\u8bed\uff1a\u7ee7\u7eed",
  "SelectSessionPrompt": "\u9009\u62e9\u4f1a\u8bdd: ",
  "RecentSessions": "\u6700\u8fd1\u7684\u4f1a\u8bdd\uff1a",
  "SelectSessionNumber": "\u8bf7\u8f93\u5165\u4f1a\u8bdd\u7f16\u53f7",
  "InvalidSelection": "\u8f93\u5165\u65e0\u6548\u3002",
  "TaskComplete": "\u4efb\u52a1\u5df2\u5168\u90e8\u5b8c\u6210\uff0c\u9000\u51fa\u3002",
  "ChinesePreview": "\u7ee7\u7eed\u6267\u884c\uff0c\u76f4\u5230\u5b8c\u6210"
}
'@

Describe "Localized prompts" {
    It "uses a Chinese default resume prompt" {
        $script:Ui.ResumePrompt | Should Be $expectedUi.ResumePrompt
        $ResumePrompt | Should Be $expectedUi.ResumePrompt
    }

    It "includes the short continue resume prompt" {
        $script:Ui.ResumePromptShort | Should Be $expectedUi.ResumePromptShort
    }

    It "includes prompt picker labels" {
        $script:Ui.SelectPromptPrompt | Should Be $expectedUi.SelectPromptPrompt
        $script:Ui.NoPromptSelected | Should Be $expectedUi.NoPromptSelected
        $script:Ui.PromptHelp | Should Be $expectedUi.PromptHelp
        $script:Ui.PromptLabelDefault | Should Be $expectedUi.PromptLabelDefault
        $script:Ui.PromptLabelShort | Should Be $expectedUi.PromptLabelShort
    }

    It "uses Chinese session and completion prompts" {
        $script:Ui.SelectSessionPrompt | Should Be $expectedUi.SelectSessionPrompt
        $script:Ui.RecentSessions | Should Be $expectedUi.RecentSessions
        $script:Ui.SelectSessionNumber | Should Be $expectedUi.SelectSessionNumber
        $script:Ui.InvalidSelection | Should Be $expectedUi.InvalidSelection
        $script:Ui.TaskComplete | Should Be $expectedUi.TaskComplete
    }
}

Describe "Get-CodexExecArgumentList" {
    It "places the output file flag before the resume subcommand" {
        $args = Get-CodexExecArgumentList -LastMessageFile "C:\Temp\last.txt" -ResumePrompt "Continue executing."

        $args | Should Be @(
            "exec",
            "--yolo",
            "-o",
            "C:\Temp\last.txt",
            "resume",
            "--last",
            "Continue executing."
        )
    }

    It "uses an explicit session id when provided" {
        $args = Get-CodexExecArgumentList -LastMessageFile "C:\Temp\last.txt" -ResumePrompt "Continue executing." -SessionId "11111111-2222-3333-4444-555555555555"

        $args | Should Be @(
            "exec",
            "--yolo",
            "-o",
            "C:\Temp\last.txt",
            "resume",
            "11111111-2222-3333-4444-555555555555",
            "Continue executing."
        )
    }

    It "can use full-auto execution instead of yolo" {
        $args = Get-CodexExecArgumentList -LastMessageFile "C:\Temp\last.txt" -ResumePrompt "Continue executing." -CodexExecutionMode "full-auto"

        $args | Should Be @(
            "exec",
            "--full-auto",
            "-o",
            "C:\Temp\last.txt",
            "resume",
            "--last",
            "Continue executing."
        )
    }

    It "can use an explicit sandbox and profile instead of yolo" {
        $args = Get-CodexExecArgumentList -LastMessageFile "C:\Temp\last.txt" -ResumePrompt "Continue executing." -CodexExecutionMode "sandbox" -CodexSandboxMode "workspace-write" -CodexProfile "safe-defaults"

        $args | Should Be @(
            "exec",
            "--profile",
            "safe-defaults",
            "--sandbox",
            "workspace-write",
            "-o",
            "C:\Temp\last.txt",
            "resume",
            "--last",
            "Continue executing."
        )
    }
}

Describe "Get-CodexExecutablePath" {
    It "prefers the installed codex.exe when present" {
        $preferredPath = Join-Path $env:APPDATA "npm\node_modules\@openai\codex\node_modules\@openai\codex-win32-x64\vendor\x86_64-pc-windows-msvc\codex\codex.exe"

        Mock Test-Path {
            param([string]$LiteralPath)
            $LiteralPath -eq $preferredPath
        }
        Mock Get-Command { throw "should not resolve generic codex" }

        $path = Get-CodexExecutablePath

        $path | Should Be $preferredPath
    }

    It "falls back to the PowerShell wrapper when codex.exe is absent" {
        $preferredExePath = Join-Path $env:APPDATA "npm\node_modules\@openai\codex\node_modules\@openai\codex-win32-x64\vendor\x86_64-pc-windows-msvc\codex\codex.exe"
        $preferredWrapperPath = Join-Path $env:APPDATA "npm\codex.ps1"

        Mock Test-Path {
            param([string]$LiteralPath)
            $LiteralPath -eq $preferredWrapperPath
        } -ParameterFilter { $LiteralPath -eq $preferredWrapperPath }
        Mock Test-Path {
            param([string]$LiteralPath)
            $false
        } -ParameterFilter { $LiteralPath -eq $preferredExePath }
        Mock Get-Command { throw "should not resolve generic codex" }

        $path = Get-CodexExecutablePath

        $path | Should Be $preferredWrapperPath
    }

    It "falls back to the resolved codex command when no preferred entry exists" {
        $preferredExePath = Join-Path $env:APPDATA "npm\node_modules\@openai\codex\node_modules\@openai\codex-win32-x64\vendor\x86_64-pc-windows-msvc\codex\codex.exe"
        $preferredWrapperPath = Join-Path $env:APPDATA "npm\codex.ps1"

        Mock Test-Path {
            param([string]$LiteralPath)
            $false
        } -ParameterFilter { $LiteralPath -eq $preferredExePath -or $LiteralPath -eq $preferredWrapperPath }
        Mock Get-Command {
            [pscustomobject]@{
                Source = "D:\Tools\codex.ps1"
            }
        } -ParameterFilter { $Name -eq "codex" }

        $path = Get-CodexExecutablePath

        $path | Should Be "D:\Tools\codex.ps1"
    }
}

Describe "Select-ResumePrompt" {
    It "returns the prompt chosen with arrow keys when fzf is unavailable" {
        Mock Get-ConsoleKeyInfo {
            if (-not $script:PromptKeyQueue) {
                $script:PromptKeyQueue = @(
                    [pscustomobject]@{ VirtualKeyCode = 40 }
                    [pscustomobject]@{ VirtualKeyCode = 13 }
                )
            }

            $next = $script:PromptKeyQueue[0]
            if ($script:PromptKeyQueue.Count -eq 1) {
                $script:PromptKeyQueue = @()
            }
            else {
                $script:PromptKeyQueue = $script:PromptKeyQueue[1..($script:PromptKeyQueue.Count - 1)]
            }
            return $next
        }
        Mock Write-Host {}
        Mock Write-MenuOptions {}

        $selected = Select-ResumePrompt

        $selected | Should Be $expectedUi.ResumePromptShort
    }

    It "passes the full prompt values to the prompt menu" {
        Mock Get-ConsoleKeyInfo { return [pscustomobject]@{ VirtualKeyCode = 13 } }
        Mock Write-Host {}
        Mock Write-MenuOptions {}

        $selected = Select-ResumePrompt

        $selected | Should Be $expectedUi.ResumePrompt
        Assert-MockCalled Write-MenuOptions -Times 1 -ParameterFilter {
            $Entries.Count -eq 2 -and
            $Entries[0].Value -eq $expectedUi.ResumePrompt -and
            $Entries[1].Value -eq $expectedUi.ResumePromptShort
        }
    }
}

Describe "Invoke-CodexCommand" {
    It "returns only the numeric exit code" {
        Mock Start-WindowTitleKeeper { return $null }
        Mock Stop-WindowTitleKeeper {}
        Mock Invoke-CodexExecutable { return 7 }

        $exitCode = Invoke-CodexCommand -ArgumentList @("exec")

        $exitCode.GetType().Name | Should Be "Int32"
        $exitCode | Should Be 7
        Assert-MockCalled Invoke-CodexExecutable -Times 1
    }

    It "starts and stops the window title keeper around execution" {
        Mock Start-WindowTitleKeeper { return "keeper-token" }
        Mock Stop-WindowTitleKeeper {}
        Mock Invoke-CodexExecutable { return 5 }

        $exitCode = Invoke-CodexCommand -ArgumentList @("exec") -WindowTitle "codex-autopilot | Turn 2/50"

        $exitCode | Should Be 5
        Assert-MockCalled Start-WindowTitleKeeper -Times 1 -ParameterFilter { $Title -eq "codex-autopilot | Turn 2/50" }
        Assert-MockCalled Stop-WindowTitleKeeper -Times 1 -ParameterFilter { $Keeper -eq "keeper-token" }
    }

    It "does not pipe codex output through Out-Host" {
        Mock Start-WindowTitleKeeper { return $null }
        Mock Stop-WindowTitleKeeper {}
        Mock Invoke-CodexExecutable {
            $global:LASTEXITCODE = 0
        }
        Mock Out-Host {}

        $exitCode = Invoke-CodexCommand -ArgumentList @("exec")

        $exitCode | Should Be 0
        Assert-MockCalled Invoke-CodexExecutable -Times 1
        Assert-MockCalled Out-Host -Times 0
    }
}

Describe "Invoke-CodexExecutable" {
    It "launches codex.exe in the same console and returns its exit code" {
        $exePath = Join-Path $env:APPDATA "npm\node_modules\@openai\codex\node_modules\@openai\codex-win32-x64\vendor\x86_64-pc-windows-msvc\codex\codex.exe"

        Mock Get-CodexExecutablePath { return $exePath }
        Mock Start-CodexProcess {
            $process = New-Object psobject -Property @{ ExitCode = 6; HasExited = $true }
            $process | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { return }
            $process | Add-Member -MemberType NoteProperty -Name StandardInput -Value ([pscustomobject]@{ Close = {} })
            return $process
        }

        $exitCode = Invoke-CodexExecutable -ArgumentList @("exec", "--yolo", "resume")

        $exitCode | Should Be 6
        Assert-MockCalled Start-CodexProcess -Times 1 -ParameterFilter {
            $FilePath -eq $exePath -and
            $ArgumentList[0] -eq "exec" -and
            $ArgumentList[1] -eq "--yolo" -and
            $ArgumentList[2] -eq "resume"
        }
    }
}

Describe "Start-CodexProcess" {
    It "starts codex with stdin redirected so terminal keypresses do not reach the child process" {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;

public class FakeStreamWriter {
    public bool Closed { get; private set; }
    public void Close() { Closed = true; }
}

public class FakeProcess {
    public FakeProcessStartInfo StartInfo { get; set; }
    public int ExitCode { get; set; }
    public bool HasExited { get; set; }
    public FakeStreamWriter StandardInput { get; private set; }
    public FakeProcess() { StandardInput = new FakeStreamWriter(); }
    public bool Start() { return true; }
    public bool WaitForExit(int timeout) { return true; }
}

public class FakeProcessStartInfo {
    public string FileName { get; set; }
    public bool UseShellExecute { get; set; }
    public bool RedirectStandardInput { get; set; }
    public bool CreateNoWindow { get; set; }
    public List<string> ArgumentList { get; private set; }
    public FakeProcessStartInfo() { ArgumentList = new List<string>(); }
}
'@
        Mock New-Object {
            param([string]$TypeName)
            switch ($TypeName) {
                'System.Diagnostics.Process' { return [FakeProcess]::new() }
                'System.Diagnostics.ProcessStartInfo' { return [FakeProcessStartInfo]::new() }
                default { throw "Unexpected type: $TypeName" }
            }
        }

        $process = Start-CodexProcess -FilePath "C:\codex.exe" -ArgumentList @("exec", "--yolo", "resume")

        $process.StandardInput.Closed | Should Be $true
        $process.StartInfo.FileName | Should Be "C:\codex.exe"
        $process.StartInfo.UseShellExecute | Should Be $false
        $process.StartInfo.RedirectStandardInput | Should Be $true
        $process.StartInfo.CreateNoWindow | Should Be $false
        @($process.StartInfo.ArgumentList) | Should Be @("exec", "--yolo", "resume")
    }

    It "falls back to the legacy Arguments string when ProcessStartInfo has no ArgumentList property" {
        Add-Type -TypeDefinition @'
using System;

public class LegacyFakeStreamWriter {
    public bool Closed { get; private set; }
    public void Close() { Closed = true; }
}

public class LegacyFakeProcess {
    public LegacyFakeProcessStartInfo StartInfo { get; set; }
    public int ExitCode { get; set; }
    public bool HasExited { get; set; }
    public LegacyFakeStreamWriter StandardInput { get; private set; }
    public LegacyFakeProcess() { StandardInput = new LegacyFakeStreamWriter(); }
    public bool Start() { return true; }
    public bool WaitForExit(int timeout) { return true; }
}

public class LegacyFakeProcessStartInfo {
    public string FileName { get; set; }
    public bool UseShellExecute { get; set; }
    public bool RedirectStandardInput { get; set; }
    public bool CreateNoWindow { get; set; }
    public string Arguments { get; set; }
}
'@
        Mock New-Object {
            param([string]$TypeName)
            switch ($TypeName) {
                'System.Diagnostics.Process' { return [LegacyFakeProcess]::new() }
                'System.Diagnostics.ProcessStartInfo' { return [LegacyFakeProcessStartInfo]::new() }
                default { throw "Unexpected type: $TypeName" }
            }
        }

        $process = Start-CodexProcess -FilePath "C:\codex.exe" -ArgumentList @("exec", "--yolo", "path with spaces")

        $process.StandardInput.Closed | Should Be $true
        $process.StartInfo.Arguments | Should Be 'exec --yolo "path with spaces"'
    }
}

Describe "Wait-ForCodexProcessExit" {
    It "returns the child exit code when the process exits normally" {
        $lastMessagePath = Join-Path $TestDrive "last-message-normal.txt"
        Set-Content -LiteralPath $lastMessagePath -Value ""
        $process = New-Object psobject -Property @{ ExitCode = 7; HasExited = $true }
        $process | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param([int]$Timeout) return $true }

        $result = Wait-ForCodexProcessExit -Process $process -Turn 1 -LastMessageFile $lastMessagePath -TurnStallTimeoutSeconds 600 -LastMessageStableSeconds 30 -LogFile (Join-Path $TestDrive "wait-normal.log")

        $result.ExitCode | Should Be 7
        $result.StallRecovered | Should Be $false
    }

    It "recovers when the last message is stable and the turn exceeds the stall timeout" {
        $lastMessagePath = Join-Path $TestDrive "last-message-stall.txt"
        $logPath = Join-Path $TestDrive "wait-stall.log"
        Set-Content -LiteralPath $lastMessagePath -Value "final answer"
        $script:WaitCallCount = 0
        $process = New-Object psobject -Property @{ Id = 4242; ExitCode = 0; HasExited = $false }
        $process | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value {
            param([int]$Timeout)
            $script:WaitCallCount += 1
            return $false
        }
        Mock Get-Date {
            if (-not $script:FakeNowIndex) { $script:FakeNowIndex = 0 }
            $times = @(
                [datetime]'2026-04-18T10:00:00'
                [datetime]'2026-04-18T10:16:00'
                [datetime]'2026-04-18T10:16:00'
            )
            $value = $times[[Math]::Min($script:FakeNowIndex, $times.Count - 1)]
            $script:FakeNowIndex += 1
            return $value
        }
        Mock Get-Item {
            [pscustomobject]@{
                Exists = $true
                Length = 128
                LastWriteTime = [datetime]'2026-04-18T10:00:10'
            }
        } -ParameterFilter { $LiteralPath -eq $lastMessagePath }
        Mock Stop-ProcessTree { $process.HasExited = $true }

        $result = Wait-ForCodexProcessExit -Process $process -Turn 1 -LastMessageFile $lastMessagePath -TurnStallTimeoutSeconds 900 -LastMessageStableSeconds 30 -LogFile $logPath

        $result.ExitCode | Should Be 0
        $result.StallRecovered | Should Be $true
        Assert-MockCalled Stop-ProcessTree -Times 1 -ParameterFilter { $ProcessId -eq 4242 }
        (Read-TextFileUtf8 -Path $logPath) | Should Match 'event=turn_stall_detected turn=1'
        (Read-TextFileUtf8 -Path $logPath) | Should Match 'event=turn_stall_recovered turn=1'
    }

    It "does not recover only because the turn is long when the last message file is still fresh" {
        $lastMessagePath = Join-Path $TestDrive "last-message-fresh.txt"
        Set-Content -LiteralPath $lastMessagePath -Value "final answer"
        $script:FreshWaitCallCount = 0
        $process = New-Object psobject -Property @{ ExitCode = 5; HasExited = $false }
        $process | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value {
            param([int]$Timeout)
            $script:FreshWaitCallCount += 1
            if ($script:FreshWaitCallCount -ge 2) {
                $this.HasExited = $true
                return $true
            }
            return $false
        }
        Mock Get-Date {
            if (-not $script:FreshNowIndex) { $script:FreshNowIndex = 0 }
            $times = @(
                [datetime]'2026-04-18T10:00:00'
                [datetime]'2026-04-18T10:16:00'
                [datetime]'2026-04-18T10:16:05'
            )
            $value = $times[[Math]::Min($script:FreshNowIndex, $times.Count - 1)]
            $script:FreshNowIndex += 1
            return $value
        }
        Mock Get-Item {
            [pscustomobject]@{
                Exists = $true
                Length = 128
                LastWriteTime = [datetime]'2026-04-18T10:15:50'
            }
        } -ParameterFilter { $LiteralPath -eq $lastMessagePath }
        Mock Stop-ProcessTree { throw "Stop-ProcessTree should not be called in this scenario." }

        $result = Wait-ForCodexProcessExit -Process $process -Turn 1 -LastMessageFile $lastMessagePath -TurnStallTimeoutSeconds 999999 -LastMessageStableSeconds 30 -LogFile (Join-Path $TestDrive "wait-fresh.log")

        $result.ExitCode | Should Be 5
        $result.StallRecovered | Should Be $false
    }
}

Describe "Read-TextFileUtf8" {
    It "reads a bom-less utf8 file without garbling Chinese" {
        $path = Join-Path $TestDrive "last-message-utf8.txt"
        $content = [string]::Concat([char]0x4E0A, [char]0x5E1D, [char]0x89C6, [char]0x89D2, [char]0x7ED3, [char]0x679C, [char]0xFF1A, [char]0x7EE7, [char]0x7EED, [char]0x63A8, [char]0x8FDB)
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)

        $actual = Read-TextFileUtf8 -Path $path

        $actual | Should Be $content
    }
}

Describe "Write-TextFileUtf8Atomic" {
    It "replaces the destination content and leaves no temp state file" {
        $path = Join-Path $TestDrive "state.json"
        [System.IO.File]::WriteAllText($path, "old", $script:Utf8Encoding)

        Write-TextFileUtf8Atomic -Path $path -Text "new"

        Read-TextFileUtf8 -Path $path | Should Be "new"
        @(Get-ChildItem -LiteralPath $TestDrive -Filter "state.json.*.tmp").Count | Should Be 0
    }
}

Describe "Get-TurnBanner" {
    It "builds a visible begin banner" {
        $expected = "========== Turn 3 / 50 {0} ==========" -f ([string]::Concat([char]0x5F00, [char]0x59CB))
        (Get-TurnBanner -Turn 3 -MaxTurns 50 -Phase "Begin") | Should Be $expected
    }

    It "builds a visible end banner" {
        $expected = "========== Turn 3 / 50 {0} ==========" -f ([string]::Concat([char]0x7ED3, [char]0x675F))
        (Get-TurnBanner -Turn 3 -MaxTurns 50 -Phase "End") | Should Be $expected
    }
}

Describe "Get-WindowTitle" {
    It "builds an in-progress title" {
        (Get-WindowTitle -Phase "Running" -Turn 3 -MaxTurns 50) | Should Be "codex-autopilot | Turn 3/50"
    }

    It "builds a completed title" {
        $expected = "codex-autopilot | {0}" -f ([string]::Concat([char]0x5DF2, [char]0x5B8C, [char]0x6210))
        (Get-WindowTitle -Phase "Completed") | Should Be $expected
    }

    It "builds a failed title with exit code" {
        $expected = "codex-autopilot | {0}(7)" -f ([string]::Concat([char]0x5931, [char]0x8D25))
        (Get-WindowTitle -Phase "Failed" -ExitCode 7) | Should Be $expected
    }
}

Describe "Resolve-SessionContext" {
    It "returns the selected session id and its original working directory" {
        $sessionsRoot = Join-Path $TestDrive "case5\\.codex\\sessions"
        $dayPath = Join-Path $sessionsRoot "2026\\04\\15"
        New-Item -ItemType Directory -Path $dayPath -Force | Out-Null

        $path = Join-Path $dayPath "rollout-2026-04-15T10-00-00-dddddddd-dddd-dddd-dddd-dddddddddddd.jsonl"
        Set-Content -LiteralPath $path -Value @'
{"timestamp":"2026-04-15T02:00:00.000Z","type":"session_meta","payload":{"id":"dddddddd-dddd-dddd-dddd-dddddddddddd","cwd":"D:\\Desktop\\target-project","agent_role":"default"}}
{"timestamp":"2026-04-15T02:00:01.000Z","type":"event_msg","payload":{"type":"user_message","message":"resume me"}}
'@

        $context = Resolve-SessionContext -SessionId "dddddddd-dddd-dddd-dddd-dddddddddddd" -SessionsDir $sessionsRoot -SessionLimit 10

        $context.SessionId | Should Be "dddddddd-dddd-dddd-dddd-dddddddddddd"
        $context.WorkingDirectory | Should Be "D:\Desktop\target-project"
    }

    It "returns the selected picker entry working directory" {
        $entries = @(
            [PSCustomObject]@{
                SessionId = "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"
                Timestamp = "2026-04-15T10-00-00"
                Preview = "pick me"
                Path = "D:\fake\rollout.jsonl"
                LastWriteTime = [datetime]"2026-04-15T10:00:00"
                WorkingDirectory = "D:\Desktop\picked-project"
            }
        )

        Mock Select-CodexSession { return $entries[0] }
        Mock Get-CodexSessionEntries { return $entries }

        $context = Resolve-SessionContext -SessionsDir "D:\fake\sessions" -SessionLimit 10

        $context.SessionId | Should Be "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"
        $context.WorkingDirectory | Should Be "D:\Desktop\picked-project"
    }
}

Describe "Get-SessionIdFromRolloutPath" {
    It "extracts the uuid from a rollout filename" {
        $sessionId = Get-SessionIdFromRolloutPath -Path "C:\Users\Administrator\.codex\sessions\2026\04\14\rollout-2026-04-14T19-30-07-019d8bc1-8036-7402-baa8-d8553d7b3738.jsonl"

        $sessionId | Should Be "019d8bc1-8036-7402-baa8-d8553d7b3738"
    }

    It "returns null for invalid rollout filenames" {
        $sessionId = Get-SessionIdFromRolloutPath -Path "C:\temp\rollout-invalid.jsonl"

        $sessionId | Should Be $null
    }
}

Describe "Get-SessionPreviewFromRollout" {
    It "returns the first user message preview" {
        $rolloutPath = Join-Path $TestDrive "rollout-2026-04-14T19-30-07-019d8bc1-8036-7402-baa8-d8553d7b3738.jsonl"
        Set-Content -LiteralPath $rolloutPath -Value @'
{"timestamp":"2026-04-14T11:30:12.807Z","type":"session_meta","payload":{"id":"019d8bc1-8036-7402-baa8-d8553d7b3738"}}
{"timestamp":"2026-04-14T11:30:12.817Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"ignored"}]}}
{"timestamp":"2026-04-14T11:30:13.000Z","type":"event_msg","payload":{"type":"user_message","message":"Continue executing until done."}}
'@

        $preview = Get-SessionPreviewFromRollout -Path $rolloutPath -MaxLength 20

        $preview | Should Be "Continue executing u"
    }

    It "falls back to no preview when no user message exists" {
        $rolloutPath = Join-Path $TestDrive "rollout-2026-04-14T19-30-07-019d8bc1-8036-7402-baa8-d8553d7b3738.jsonl"
        Set-Content -LiteralPath $rolloutPath -Value @'
{"timestamp":"2026-04-14T11:30:12.807Z","type":"session_meta","payload":{"id":"019d8bc1-8036-7402-baa8-d8553d7b3738"}}
'@

        $preview = Get-SessionPreviewFromRollout -Path $rolloutPath

        $preview | Should Be "(no preview)"
    }

    It "reads utf8 Chinese previews correctly" {
        $rolloutPath = Join-Path $TestDrive "rollout-2026-04-14T19-30-07-019d8bc1-8036-7402-baa8-d8553d7b3738.jsonl"
        Set-Content -LiteralPath $rolloutPath -Encoding UTF8 -Value @'
{"timestamp":"2026-04-14T11:30:12.807Z","type":"session_meta","payload":{"id":"019d8bc1-8036-7402-baa8-d8553d7b3738"}}
{"timestamp":"2026-04-14T11:30:13.000Z","type":"event_msg","payload":{"type":"user_message","message":"\u7ee7\u7eed\u6267\u884c\uff0c\u76f4\u5230\u5b8c\u6210"}}
'@

        $preview = Get-SessionPreviewFromRollout -Path $rolloutPath

        $preview | Should Be $expectedUi.ChinesePreview
    }
}

Describe "Get-CodexSessionEntries" {
    It "lists recent rollout files with parsed metadata" {
        $sessionsRoot = Join-Path $TestDrive "case1\\.codex\\sessions"
        $dayPath = Join-Path $sessionsRoot "2026\\04\\14"
        New-Item -ItemType Directory -Path $dayPath -Force | Out-Null

        $oldPath = Join-Path $dayPath "rollout-2026-04-14T18-00-00-aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jsonl"
        $newPath = Join-Path $dayPath "rollout-2026-04-14T19-30-07-bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb.jsonl"
        Set-Content -LiteralPath $oldPath -Value @'
{"timestamp":"2026-04-14T11:30:12.807Z","type":"session_meta","payload":{"id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","cwd":"D:\\Desktop\\old","agent_role":"default"}}
{"timestamp":"2026-04-14T11:30:13.000Z","type":"event_msg","payload":{"type":"user_message","message":"older"}}
'@
        Set-Content -LiteralPath $newPath -Value @'
{"timestamp":"2026-04-14T11:30:12.807Z","type":"session_meta","payload":{"id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","cwd":"D:\\Desktop\\new","agent_role":"default"}}
{"timestamp":"2026-04-14T11:30:13.000Z","type":"event_msg","payload":{"type":"user_message","message":"newer"}}
'@

        $entries = @(Get-CodexSessionEntries -SessionsDir $sessionsRoot -MaxCount 10)

        $entries.Count | Should Be 2
        $entries[0].SessionId | Should Be "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
        $entries[0].Preview | Should Be "newer"
        $entries[1].SessionId | Should Be "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    }

    It "falls back to cwd when a primary session has no user preview" {
        $sessionsRoot = Join-Path $TestDrive "case4\\.codex\\sessions"
        $dayPath = Join-Path $sessionsRoot "2026\\04\\14"
        New-Item -ItemType Directory -Path $dayPath -Force | Out-Null

        $path = Join-Path $dayPath "rollout-2026-04-14T20-00-00-cccccccc-cccc-cccc-cccc-cccccccccccc.jsonl"
        Set-Content -LiteralPath $path -Value @'
{"timestamp":"2026-04-14T11:30:12.807Z","type":"session_meta","payload":{"id":"cccccccc-cccc-cccc-cccc-cccccccccccc","cwd":"D:\\Desktop\\fallback","agent_role":"default"}}
'@

        $entries = @(Get-CodexSessionEntries -SessionsDir $sessionsRoot -MaxCount 10)

        $entries.Count | Should Be 1
        $entries[0].Preview | Should Be "No user message | D:\Desktop\fallback"
        $entries[0].WorkingDirectory | Should Be "D:\Desktop\fallback"
    }

    It "excludes subagent sessions from the picker" {
        $sessionsRoot = Join-Path $TestDrive "case2\\.codex\\sessions"
        $dayPath = Join-Path $sessionsRoot "2026\\04\\14"
        New-Item -ItemType Directory -Path $dayPath -Force | Out-Null

        $mainPath = Join-Path $dayPath "rollout-2026-04-14T19-30-07-11111111-1111-1111-1111-111111111111.jsonl"
        $subagentPath = Join-Path $dayPath "rollout-2026-04-14T19-31-07-22222222-2222-2222-2222-222222222222.jsonl"

        Set-Content -LiteralPath $mainPath -Value @'
{"timestamp":"2026-04-14T11:30:12.807Z","type":"session_meta","payload":{"id":"11111111-1111-1111-1111-111111111111","cwd":"D:\\Desktop","originator":"codex-tui","agent_role":"default"}}
{"timestamp":"2026-04-14T11:30:13.000Z","type":"event_msg","payload":{"type":"user_message","message":"main"}}
'@

        Set-Content -LiteralPath $subagentPath -Value @'
{"timestamp":"2026-04-14T11:30:12.807Z","type":"session_meta","payload":{"id":"22222222-2222-2222-2222-222222222222","cwd":"D:\\Desktop","originator":"codex-tui","agent_role":"worker","source":{"subagent":{"thread_spawn":{"parent_thread_id":"11111111-1111-1111-1111-111111111111"}}}}}
{"timestamp":"2026-04-14T11:30:13.000Z","type":"event_msg","payload":{"type":"user_message","message":"subagent"}}
'@

        $entries = @(Get-CodexSessionEntries -SessionsDir $sessionsRoot -MaxCount 10)

        $entries.Count | Should Be 1
        $entries[0].SessionId | Should Be "11111111-1111-1111-1111-111111111111"
    }

    It "applies the max count after excluding subagent sessions" {
        $sessionsRoot = Join-Path $TestDrive "case3\\.codex\\sessions"
        $dayPath = Join-Path $sessionsRoot "2026\\04\\14"
        New-Item -ItemType Directory -Path $dayPath -Force | Out-Null

        1..4 | ForEach-Object {
            $id = ('{0:D12}' -f $_)
            $path = Join-Path $dayPath ("rollout-2026-04-14T19-3{0}-07-00000000-0000-0000-0000-{1}.jsonl" -f $_, $id)
            Set-Content -LiteralPath $path -Value ('{{"timestamp":"2026-04-14T11:30:12.807Z","type":"session_meta","payload":{{"id":"00000000-0000-0000-0000-{0}","agent_role":"worker","source":{{"subagent":{{"thread_spawn":{{"parent_thread_id":"p"}}}}}}}}}}' -f $id)
        }

        5..7 | ForEach-Object {
            $id = ('{0:D12}' -f $_)
            $path = Join-Path $dayPath ("rollout-2026-04-14T19-4{0}-07-11111111-1111-1111-1111-{1}.jsonl" -f $_, $id)
            Set-Content -LiteralPath $path -Value ('{{"timestamp":"2026-04-14T11:30:12.807Z","type":"session_meta","payload":{{"id":"11111111-1111-1111-1111-{0}","agent_role":"default"}}}}' -f $id)
        }

        $entries = @(Get-CodexSessionEntries -SessionsDir $sessionsRoot -MaxCount 2)

        $entries.Count | Should Be 2
        $entries[0].SessionId | Should Be "11111111-1111-1111-1111-000000000007"
        $entries[1].SessionId | Should Be "11111111-1111-1111-1111-000000000006"
    }
}

Describe "Invoke-CodexAutopilot" {
    It "runs codex from the resumed session working directory" {
        $lastMessagePath = Join-Path $TestDrive "last-message.txt"
        $workingDirectory = Join-Path $TestDrive "resumed-project"
        $script:CapturedCodexWorkingDirectory = $null
        Set-Content -LiteralPath $lastMessagePath -Value "[TASK_COMPLETE]"
        New-Item -ItemType Directory -Path $workingDirectory -Force | Out-Null

        Mock Get-CodexExecArgumentList { return @("exec", "--yolo", "-o", $lastMessagePath, "resume", "ffffffff-ffff-ffff-ffff-ffffffffffff", "Continue") }
        Mock Invoke-CodexCommand {
            $script:CapturedCodexWorkingDirectory = (Get-Location).Path
            return 0
        }
        Mock Start-Sleep {}

        $originalLocation = Get-Location
        Push-Location $TestDrive
        try {
            $exitCode = Invoke-CodexAutopilot -MaxTurns 1 -SleepSeconds 0 -LastMessageFile $lastMessagePath -ResumePrompt "Continue" -SessionId "ffffffff-ffff-ffff-ffff-ffffffffffff" -WorkingDirectory $workingDirectory

            $exitCode | Should Be 0
            Assert-MockCalled Invoke-CodexCommand -Times 1
            Split-Path -Path $script:CapturedCodexWorkingDirectory -Leaf | Should Be "resumed-project"
        }
        finally {
            Pop-Location
            Set-Location $originalLocation
        }
    }

    It "updates the window title through running and max-turn completion states" {
        $lastMessagePath = Join-Path $TestDrive "last-message-title.txt"
        $completedTitle = "codex-autopilot | {0}" -f ([string]::Concat([char]0x5DF2, [char]0x5B8C, [char]0x6210))
        Set-Content -LiteralPath $lastMessagePath -Value "[TASK_COMPLETE]"

        Mock Get-CodexExecArgumentList { return @("exec", "--yolo", "-o", $lastMessagePath, "resume", "ffffffff-ffff-ffff-ffff-ffffffffffff", "Continue") }
        Mock Invoke-CodexCommand { return 0 }
        Mock Start-Sleep {}
        Mock Set-WindowTitle {}

        $exitCode = Invoke-CodexAutopilot -MaxTurns 1 -SleepSeconds 0 -LastMessageFile $lastMessagePath -ResumePrompt "Continue" -SessionId "ffffffff-ffff-ffff-ffff-ffffffffffff"

        $exitCode | Should Be 0
        Assert-MockCalled Set-WindowTitle -Times 1 -ParameterFilter { $Title -eq "codex-autopilot | Turn 1/1" }
        Assert-MockCalled Set-WindowTitle -Times 1 -ParameterFilter { $Title -eq $completedTitle }
    }

    It "updates the window title to a failure state when codex exits non-zero" {
        $lastMessagePath = Join-Path $TestDrive "last-message-fail.txt"
        $failedTitle = "codex-autopilot | {0}(9)" -f ([string]::Concat([char]0x5931, [char]0x8D25))
        Set-Content -LiteralPath $lastMessagePath -Value ""

        Mock Get-CodexExecArgumentList { return @("exec", "--yolo", "-o", $lastMessagePath, "resume", "ffffffff-ffff-ffff-ffff-ffffffffffff", "Continue") }
        Mock Invoke-CodexCommand { return 9 }
        Mock Start-Sleep {}
        Mock Set-WindowTitle {}

        $exitCode = Invoke-CodexAutopilot -MaxTurns 1 -SleepSeconds 0 -LastMessageFile $lastMessagePath -ResumePrompt "Continue" -SessionId "ffffffff-ffff-ffff-ffff-ffffffffffff"

        $exitCode | Should Be 9
        Assert-MockCalled Set-WindowTitle -Times 1 -ParameterFilter { $Title -eq "codex-autopilot | Turn 1/1" }
        Assert-MockCalled Set-WindowTitle -Times 1 -ParameterFilter { $Title -eq $failedTitle }
    }

    It "ignores the completion token in the last message and waits for max turns" {
        $lastMessagePath = Join-Path $TestDrive "last-message-log.txt"
        $logPath = Join-Path $TestDrive "autopilot.log"
        Set-Content -LiteralPath $lastMessagePath -Value "[TASK_COMPLETE]"

        Mock Get-CodexExecArgumentList { return @("exec") }
        Mock Invoke-CodexCommand { return 0 }
        Mock Start-Sleep {}
        Mock Set-WindowTitle {}

        $exitCode = Invoke-CodexAutopilot -MaxTurns 1 -SleepSeconds 0 -LastMessageFile $lastMessagePath -ResumePrompt "Continue" -SessionId "ffffffff-ffff-ffff-ffff-ffffffffffff" -LogFile $logPath

        $exitCode | Should Be 0
        $logText = Read-TextFileUtf8 -Path $logPath
        $logText | Should Match 'event=turn_start turn=1 max_turns=1'
        $logText | Should Match 'event=exec_exit turn=1 exit_code=0'
        $logText | Should Match 'event=stop reason=max_turns_reached turn=1 exit_code=0'
        $logText | Should Not Match 'event=stop reason=task_complete'
    }

    It "continues into the next turn after turn 1 succeeds" {
        $lastMessagePath = Join-Path $TestDrive "last-message-next-turn.txt"
        $logPath = Join-Path $TestDrive "autopilot-next-turn.log"
        Set-Content -LiteralPath $lastMessagePath -Value "[TASK_COMPLETE]"

        Mock Get-CodexExecArgumentList { return @("exec") }
        Mock Invoke-CodexCommand { return 0 }
        Mock Start-Sleep {}
        Mock Set-WindowTitle {}

        $exitCode = Invoke-CodexAutopilot -MaxTurns 2 -SleepSeconds 0 -LastMessageFile $lastMessagePath -ResumePrompt "Continue" -SessionId "ffffffff-ffff-ffff-ffff-ffffffffffff" -LogFile $logPath

        $exitCode | Should Be 0
        Assert-MockCalled Invoke-CodexCommand -Times 2
        Assert-MockCalled Set-WindowTitle -Times 1 -ParameterFilter { $Title -eq "codex-autopilot | Turn 1/2" }
        Assert-MockCalled Set-WindowTitle -Times 1 -ParameterFilter { $Title -eq "codex-autopilot | Turn 2/2" }
        $logText = Read-TextFileUtf8 -Path $logPath
        $logText | Should Match 'event=turn_end turn=1 exit_code=0'
        $logText | Should Match 'event=sleep_start turn=1 seconds=0'
        $logText | Should Match 'event=sleep_end turn=1'
        $logText | Should Match 'event=loop_continue next_turn=2'
    }

    It "writes stop reason logs for non-zero exit" {
        $lastMessagePath = Join-Path $TestDrive "last-message-log-fail.txt"
        $logPath = Join-Path $TestDrive "autopilot-fail.log"
        Set-Content -LiteralPath $lastMessagePath -Value ""

        Mock Get-CodexExecArgumentList { return @("exec") }
        Mock Invoke-CodexCommand { return 12 }
        Mock Start-Sleep {}
        Mock Set-WindowTitle {}

        $exitCode = Invoke-CodexAutopilot -MaxTurns 1 -SleepSeconds 0 -LastMessageFile $lastMessagePath -ResumePrompt "Continue" -SessionId "ffffffff-ffff-ffff-ffff-ffffffffffff" -LogFile $logPath

        $exitCode | Should Be 12
        $logText = Read-TextFileUtf8 -Path $logPath
        $logText | Should Match 'event=exec_exit turn=1 exit_code=12'
        $logText | Should Match 'event=stop reason=exec_exit_nonzero turn=1 exit_code=12'
    }

    It "logs codex execution exceptions before rethrowing" {
        $lastMessagePath = Join-Path $TestDrive "last-message-exception.txt"
        $logPath = Join-Path $TestDrive "autopilot-exception.log"
        Set-Content -LiteralPath $lastMessagePath -Value ""

        Mock Get-CodexExecArgumentList { return @("exec") }
        Mock Invoke-CodexCommand { throw "codex hung up" }
        Mock Start-Sleep {}
        Mock Set-WindowTitle {}

        { Invoke-CodexAutopilot -MaxTurns 2 -SleepSeconds 0 -LastMessageFile $lastMessagePath -ResumePrompt "Continue" -SessionId "ffffffff-ffff-ffff-ffff-ffffffffffff" -LogFile $logPath } | Should Throw "codex hung up"
        $logText = Read-TextFileUtf8 -Path $logPath
        $logText | Should Match 'event=exec_exception turn=1 message=codex hung up'
        $logText | Should Not Match 'event=exec_exit turn=1'
    }

    It "writes stop reason logs for max turns reached" {
        $lastMessagePath = Join-Path $TestDrive "last-message-log-max.txt"
        $logPath = Join-Path $TestDrive "autopilot-max.log"
        Set-Content -LiteralPath $lastMessagePath -Value "still running"

        Mock Get-CodexExecArgumentList { return @("exec") }
        Mock Invoke-CodexCommand { return 0 }
        Mock Start-Sleep {}
        Mock Set-WindowTitle {}

        $exitCode = Invoke-CodexAutopilot -MaxTurns 1 -SleepSeconds 0 -LastMessageFile $lastMessagePath -ResumePrompt "Continue" -SessionId "ffffffff-ffff-ffff-ffff-ffffffffffff" -LogFile $logPath

        $exitCode | Should Be 0
        $logText = Read-TextFileUtf8 -Path $logPath
        $logText | Should Match 'event=stop reason=max_turns_reached turn=1 exit_code=0'
    }

    It "continues into the next turn after stall recovery" {
        $lastMessagePath = Join-Path $TestDrive "last-message-stall-next-turn.txt"
        $logPath = Join-Path $TestDrive "autopilot-stall-next-turn.log"
        Set-Content -LiteralPath $lastMessagePath -Value "final answer"
        $script:CommandResults = @(
            [pscustomobject]@{ ExitCode = 0; StallRecovered = $true }
            [pscustomobject]@{ ExitCode = 0; StallRecovered = $false }
        )

        Mock Get-CodexExecArgumentList { return @("exec") }
        Mock Invoke-CodexCommand {
            $next = $script:CommandResults[0]
            if ($script:CommandResults.Count -eq 1) {
                $script:CommandResults = @()
            }
            else {
                $script:CommandResults = $script:CommandResults[1..($script:CommandResults.Count - 1)]
            }
            return $next
        }
        Mock Start-Sleep {}
        Mock Set-WindowTitle {}

        $exitCode = Invoke-CodexAutopilot -MaxTurns 2 -SleepSeconds 0 -LastMessageFile $lastMessagePath -ResumePrompt "Continue" -SessionId "ffffffff-ffff-ffff-ffff-ffffffffffff" -LogFile $logPath -TurnStallTimeoutSeconds 900 -LastMessageStableSeconds 30

        $exitCode | Should Be 0
        Assert-MockCalled Invoke-CodexCommand -Times 2
        (Read-TextFileUtf8 -Path $logPath) | Should Match 'event=loop_continue next_turn=2'
    }

    It "writes a run state file with the latest turn and stop reason" {
        $lastMessagePath = Join-Path $TestDrive "last-message-state.txt"
        $runStatePath = Join-Path $TestDrive "run-state.json"
        Set-Content -LiteralPath $lastMessagePath -Value "stateful answer"

        Mock Get-CodexExecArgumentList { return @("exec") }
        Mock Invoke-CodexCommand { return 0 }
        Mock Start-Sleep {}
        Mock Set-WindowTitle {}

        $exitCode = Invoke-CodexAutopilot -MaxTurns 1 -SleepSeconds 0 -LastMessageFile $lastMessagePath -ResumePrompt "Continue" -SessionId "ffffffff-ffff-ffff-ffff-ffffffffffff" -WorkingDirectory $TestDrive -RunStateFile $runStatePath

        $exitCode | Should Be 0
        Test-Path -LiteralPath $runStatePath | Should Be $true
        $state = Get-Content -LiteralPath $runStatePath -Raw | ConvertFrom-Json
        $state.session_id | Should Be "ffffffff-ffff-ffff-ffff-ffffffffffff"
        $state.turn | Should Be 1
        $state.max_turns | Should Be 1
        $state.last_exit_code | Should Be 0
        $state.stop_reason | Should Be "max_turns_reached"
        $state.last_message_length | Should Be (Read-TextFileUtf8 -Path $lastMessagePath).Length
        $state.working_directory.Trim() | Should Be ([string]$TestDrive).Trim()
    }

    It "resumes from the next turn when the run state ended with loop_continue" {
        $lastMessagePath = Join-Path $TestDrive "last-message-resume-state.txt"
        $runStatePath = Join-Path $TestDrive "run-state-resume.json"
        $logPath = Join-Path $TestDrive "autopilot-resume-state.log"
        Set-Content -LiteralPath $lastMessagePath -Value "resume answer"
        @{
            session_id = "ffffffff-ffff-ffff-ffff-ffffffffffff"
            working_directory = ""
            turn = 1
            max_turns = 3
            last_exit_code = 0
            stop_reason = "loop_continue"
            stall_recovered = $false
            last_message_length = 13
            last_message_sha256 = "ignored"
        } | ConvertTo-Json | Set-Content -LiteralPath $runStatePath

        Mock Get-CodexExecArgumentList { return @("exec") }
        Mock Invoke-CodexCommand { return 0 }
        Mock Start-Sleep {}
        Mock Set-WindowTitle {}

        $exitCode = Invoke-CodexAutopilot -MaxTurns 3 -SleepSeconds 0 -LastMessageFile $lastMessagePath -ResumePrompt "Continue" -SessionId "ffffffff-ffff-ffff-ffff-ffffffffffff" -LogFile $logPath -RunStateFile $runStatePath

        $exitCode | Should Be 0
        Assert-MockCalled Invoke-CodexCommand -Times 2
        $logText = Read-TextFileUtf8 -Path $logPath
        $logText | Should Match 'event=run_state_restored turn=1 next_turn=2'
        $logText | Should Not Match 'event=turn_start turn=1'
        $logText | Should Match 'event=turn_start turn=2'
        $logText | Should Match 'event=turn_start turn=3'
    }

    It "does not resume a run state that already reached max turns" {
        $lastMessagePath = Join-Path $TestDrive "last-message-completed-state.txt"
        $runStatePath = Join-Path $TestDrive "run-state-completed.json"
        $logPath = Join-Path $TestDrive "autopilot-completed-state.log"
        Set-Content -LiteralPath $lastMessagePath -Value "done"
        @{
            session_id = "ffffffff-ffff-ffff-ffff-ffffffffffff"
            working_directory = ""
            turn = 3
            max_turns = 3
            last_exit_code = 0
            stop_reason = "max_turns_reached"
        } | ConvertTo-Json | Set-Content -LiteralPath $runStatePath

        Mock Get-CodexExecArgumentList { return @("exec") }
        Mock Invoke-CodexCommand { throw "should not execute codex when run state is complete" }
        Mock Start-Sleep {}
        Mock Set-WindowTitle {}

        $exitCode = Invoke-CodexAutopilot -MaxTurns 3 -SleepSeconds 0 -LastMessageFile $lastMessagePath -ResumePrompt "Continue" -SessionId "ffffffff-ffff-ffff-ffff-ffffffffffff" -LogFile $logPath -RunStateFile $runStatePath

        $exitCode | Should Be 0
        (Read-TextFileUtf8 -Path $logPath) | Should Match 'event=run_state_complete turn=3 max_turns=3'
    }

    It "resumes a completed run state when max turns is increased" {
        $lastMessagePath = Join-Path $TestDrive "last-message-completed-extended.txt"
        $runStatePath = Join-Path $TestDrive "run-state-completed-extended.json"
        $logPath = Join-Path $TestDrive "autopilot-completed-extended.log"
        Set-Content -LiteralPath $lastMessagePath -Value "extended"
        @{
            session_id = "ffffffff-ffff-ffff-ffff-ffffffffffff"
            working_directory = ""
            turn = 3
            max_turns = 3
            last_exit_code = 0
            stop_reason = "max_turns_reached"
        } | ConvertTo-Json | Set-Content -LiteralPath $runStatePath

        Mock Get-CodexExecArgumentList { return @("exec") }
        Mock Invoke-CodexCommand { return 0 }
        Mock Start-Sleep {}
        Mock Set-WindowTitle {}

        $exitCode = Invoke-CodexAutopilot -MaxTurns 5 -SleepSeconds 0 -LastMessageFile $lastMessagePath -ResumePrompt "Continue" -SessionId "ffffffff-ffff-ffff-ffff-ffffffffffff" -LogFile $logPath -RunStateFile $runStatePath

        $exitCode | Should Be 0
        Assert-MockCalled Invoke-CodexCommand -Times 2
        $logText = Read-TextFileUtf8 -Path $logPath
        $logText | Should Match 'event=run_state_restored turn=3 next_turn=4 reason=max_turns_extended'
        $logText | Should Match 'event=turn_start turn=4'
        $logText | Should Match 'event=turn_start turn=5'
    }

    It "ignores a run state with invalid numeric fields" {
        $lastMessagePath = Join-Path $TestDrive "last-message-invalid-state.txt"
        $runStatePath = Join-Path $TestDrive "run-state-invalid.json"
        $logPath = Join-Path $TestDrive "autopilot-invalid-state.log"
        Set-Content -LiteralPath $lastMessagePath -Value "invalid"
        @{
            session_id = "ffffffff-ffff-ffff-ffff-ffffffffffff"
            working_directory = ""
            turn = "abc"
            max_turns = 3
            last_exit_code = 0
            stop_reason = "loop_continue"
        } | ConvertTo-Json | Set-Content -LiteralPath $runStatePath

        Mock Get-CodexExecArgumentList { return @("exec") }
        Mock Invoke-CodexCommand { return 0 }
        Mock Start-Sleep {}
        Mock Set-WindowTitle {}

        $exitCode = Invoke-CodexAutopilot -MaxTurns 1 -SleepSeconds 0 -LastMessageFile $lastMessagePath -ResumePrompt "Continue" -SessionId "ffffffff-ffff-ffff-ffff-ffffffffffff" -LogFile $logPath -RunStateFile $runStatePath

        $exitCode | Should Be 0
        $logText = Read-TextFileUtf8 -Path $logPath
        $logText | Should Match 'event=run_state_ignored reason=invalid_fields'
        $logText | Should Match 'event=turn_start turn=1'
    }
}
Describe "Initialize-ConsoleUtf8" {
    It "sets console and pipeline encodings to utf8" {
        Initialize-ConsoleUtf8

        [Console]::OutputEncoding.WebName | Should Be "utf-8"
        [Console]::InputEncoding.WebName | Should Be "utf-8"
        $OutputEncoding.WebName | Should Be "utf-8"
    }
}

Describe "codex-autopilot.cmd" {
    It "invokes the PowerShell script in the same directory" {
        $content = Get-Content -LiteralPath "D:\Desktop\codex-autopilot\codex-autopilot.cmd" -Raw

        $content | Should Match 'powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0codex-autopilot\.ps1" %\*'
    }
}
