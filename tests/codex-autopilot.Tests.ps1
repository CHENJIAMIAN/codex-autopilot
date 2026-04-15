$env:CODEX_AUTOPILOT_IMPORT_ONLY = "1"
. "D:\Desktop\codex-autopilot\codex-autopilot.ps1"
Remove-Item Env:CODEX_AUTOPILOT_IMPORT_ONLY -ErrorAction SilentlyContinue

$expectedUi = ConvertFrom-Json @'
{
  "ResumePrompt": "1.\u5148\u7528\u4e0a\u5e1d\u89c6\u89d2\u770b\u5f53\u524d\u72b6\u6001\u8ddd\u79bb\u539f\u59cb\u76ee\u6807\u591a\u8fdc 2.\u63d0\u4ea4\u6240\u6709\u66f4\u6539\u4f5c\u4e3a\u65b0\u5f81\u7a0b\u7684\u57fa\u7ebf 3.\u7ee7\u7eed\u6cbf\u7740\u539f\u59cb\u76ee\u6807\u63a8\u8fdb,\u8981\u9ad8\u6548\u5229\u7528\u5b50\u4ee3\u7406\u52a0\u901f\u63a8\u8fdb\u901f\u5ea6",
  "SelectSessionPrompt": "\u9009\u62e9\u4f1a\u8bdd: ",
  "RecentSessions": "\u6700\u8fd1\u7684\u4f1a\u8bdd\uff1a",
  "SelectSessionNumber": "\u8bf7\u8f93\u5165\u4f1a\u8bdd\u7f16\u53f7",
  "InvalidSelection": "\u8f93\u5165\u65e0\u6548\u3002",
  "TaskComplete": "\u4efb\u52a1\u5df2\u5168\u90e8\u5b8c\u6210\uff0c\u9000\u51fa\u3002",
  "ChinesePreview": "\u7ee7\u7eed\u6267\u884c\uff0c\u76f4\u5230\u5b8c\u6210"
}
'@

Describe "Test-TaskCompletionSignal" {
    It "detects the explicit completion token" {
        Test-TaskCompletionSignal -Message "Finished successfully.`n[TASK_COMPLETE]" | Should Be $true
    }

    It "detects fallback pattern matches case-insensitively" {
        Test-TaskCompletionSignal -Message "All done, nothing left to do." -DonePattern "all done|nothing left" | Should Be $true
    }

    It "returns false when neither token nor pattern matches" {
        Test-TaskCompletionSignal -Message "Continue working." -DonePattern "all done" | Should Be $false
    }
}

Describe "Localized prompts" {
    It "uses a Chinese default resume prompt" {
        $script:Ui.ResumePrompt | Should Be $expectedUi.ResumePrompt
        $ResumePrompt | Should Be $expectedUi.ResumePrompt
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
}

Describe "Invoke-CodexCommand" {
    It "returns only the numeric exit code" {
        Mock Start-WindowTitleKeeper { return $null }
        Mock Stop-WindowTitleKeeper {}
        Mock Invoke-CodexExecutable {
            Write-Output "demo output"
            $global:LASTEXITCODE = 7
        }

        $exitCode = Invoke-CodexCommand -ArgumentList @("exec")

        $exitCode.GetType().Name | Should Be "Int32"
        $exitCode | Should Be 7
        Assert-MockCalled Invoke-CodexExecutable -Times 1
    }

    It "starts and stops the window title keeper around execution" {
        Mock Start-WindowTitleKeeper { return "keeper-token" }
        Mock Stop-WindowTitleKeeper {}
        Mock Invoke-CodexExecutable {
            $global:LASTEXITCODE = 5
        }

        $exitCode = Invoke-CodexCommand -ArgumentList @("exec") -WindowTitle "codex-autopilot | Turn 2/50"

        $exitCode | Should Be 5
        Assert-MockCalled Start-WindowTitleKeeper -Times 1 -ParameterFilter { $Title -eq "codex-autopilot | Turn 2/50" }
        Assert-MockCalled Stop-WindowTitleKeeper -Times 1 -ParameterFilter { $Keeper -eq "keeper-token" }
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
        Mock Test-TaskCompletionSignal { return $true }
        Mock Start-Sleep {}

        $originalLocation = Get-Location
        Push-Location $TestDrive
        try {
            $exitCode = Invoke-CodexAutopilot -MaxTurns 1 -SleepSeconds 0 -LastMessageFile $lastMessagePath -ResumePrompt "Continue" -SessionId "ffffffff-ffff-ffff-ffff-ffffffffffff" -WorkingDirectory $workingDirectory -DonePattern "" -CompletionToken "[TASK_COMPLETE]"

            $exitCode | Should Be 0
            Assert-MockCalled Invoke-CodexCommand -Times 1
            $script:CapturedCodexWorkingDirectory | Should Be $workingDirectory
        }
        finally {
            Pop-Location
            Set-Location $originalLocation
        }
    }

    It "updates the window title through running and completed states" {
        $lastMessagePath = Join-Path $TestDrive "last-message-title.txt"
        $completedTitle = "codex-autopilot | {0}" -f ([string]::Concat([char]0x5DF2, [char]0x5B8C, [char]0x6210))
        Set-Content -LiteralPath $lastMessagePath -Value "[TASK_COMPLETE]"

        Mock Get-CodexExecArgumentList { return @("exec", "--yolo", "-o", $lastMessagePath, "resume", "ffffffff-ffff-ffff-ffff-ffffffffffff", "Continue") }
        Mock Invoke-CodexCommand { return 0 }
        Mock Test-TaskCompletionSignal { return $true }
        Mock Start-Sleep {}
        Mock Set-WindowTitle {}

        $exitCode = Invoke-CodexAutopilot -MaxTurns 1 -SleepSeconds 0 -LastMessageFile $lastMessagePath -ResumePrompt "Continue" -SessionId "ffffffff-ffff-ffff-ffff-ffffffffffff" -DonePattern "" -CompletionToken "[TASK_COMPLETE]"

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

        $exitCode = Invoke-CodexAutopilot -MaxTurns 1 -SleepSeconds 0 -LastMessageFile $lastMessagePath -ResumePrompt "Continue" -SessionId "ffffffff-ffff-ffff-ffff-ffffffffffff" -DonePattern "" -CompletionToken "[TASK_COMPLETE]"

        $exitCode | Should Be 9
        Assert-MockCalled Set-WindowTitle -Times 1 -ParameterFilter { $Title -eq "codex-autopilot | Turn 1/1" }
        Assert-MockCalled Set-WindowTitle -Times 1 -ParameterFilter { $Title -eq $failedTitle }
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

Describe "Set-CodexDeveloperInstructions" {
    It "adds the completion token instruction when missing" {
        $configPath = Join-Path $TestDrive "config.toml"
        Set-Content -LiteralPath $configPath -Value @"
model = "gpt-5.4"
service_tier = "fast"
"@

        Set-CodexDeveloperInstructions -ConfigPath $configPath

        $updated = Get-Content -LiteralPath $configPath -Raw
        $updated | Should Match 'developer_instructions = "When the entire task is truly and fully complete with nothing left to do, end your final message with the exact token: \[TASK_COMPLETE\]\. Do not use this token unless the task is genuinely finished\."'
    }

    It "does not duplicate the instruction when already present" {
        $configPath = Join-Path $TestDrive "config.toml"
        Set-Content -LiteralPath $configPath -Value @'
developer_instructions = "When the entire task is truly and fully complete with nothing left to do, end your final message with the exact token: [TASK_COMPLETE]. Do not use this token unless the task is genuinely finished."
model = "gpt-5.4"
'@

        Set-CodexDeveloperInstructions -ConfigPath $configPath

        $updated = Get-Content -LiteralPath $configPath -Raw
        ([regex]::Matches($updated, [regex]::Escape('developer_instructions = "When the entire task is truly and fully complete with nothing left to do, end your final message with the exact token: [TASK_COMPLETE]. Do not use this token unless the task is genuinely finished."'))).Count | Should Be 1
    }
}

Describe "codex-autopilot.cmd" {
    It "invokes the PowerShell script in the same directory" {
        $content = Get-Content -LiteralPath "D:\Desktop\codex-autopilot\codex-autopilot.cmd" -Raw

        $content | Should Match 'powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0codex-autopilot\.ps1" %\*'
    }
}
