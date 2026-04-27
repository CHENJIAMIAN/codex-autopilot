# codex-autopilot

Windows autopilot wrapper for continuing existing Codex sessions turn by turn.

It is built for a simple workflow:

- pick an existing Codex session
- resume it with a configurable prompt
- keep running turns until you stop, hit a safety limit, or Codex exits non-zero

## What It Does

- Resume an existing Codex session by picker or explicit `SessionId`
- Continue automatically for multiple turns with a configurable `MaxTurns`
- Persist run state to `run-state.json` so interrupted runs can continue from the next turn
- Retry transient non-zero `codex exec` exits without consuming extra turn budget
- Recover conservatively from long stalled turns when the last message is already stable
- Show session working directory in the picker
- Prefer full session history when `fzf` is available, with fallback to numbered selection
- Load resume prompt options from `resume-prompts.txt` so prompt changes do not require code edits

## Requirements

- Windows
- PowerShell
- Codex CLI available as `codex`
- Optional: `fzf` for searchable session selection

## Files

- `codex-autopilot.ps1`: main script
- `codex-autopilot.cmd`: double-clickable launcher
- `resume-prompts.txt`: one resume prompt option per line
- `tests/codex-autopilot.Tests.ps1`: Pester tests

## Quick Start

Run the launcher:

```powershell
D:\Desktop\codex-autopilot\codex-autopilot.cmd
```

Or run the script directly:

```powershell
powershell -ExecutionPolicy Bypass -File D:\Desktop\codex-autopilot\codex-autopilot.ps1
```

If you do not pass `-ResumePrompt`, the script opens a prompt picker first.

## Session Picker

- With `fzf`: load all primary sessions and search interactively
- Without `fzf`: show a numbered recent-session list limited by `SessionLimit`
- The time column is based on the session rollout file's last write time, which reflects last use better than original creation time
- The picker also shows each session's working directory

If a selected session does not have a recorded working directory, the script stops with an explicit error instead of resuming in the wrong directory.

## Resume Prompts

Prompt options live in `resume-prompts.txt`.

- One line = one selectable prompt
- Blank lines are ignored
- The first line becomes the default `ResumePrompt`
- If the file is missing or empty, the script falls back to built-in defaults

Example:

```text
1.先用上帝视角看当前状态距离最终阶段的最终目标多远 2.提交所有更改作为新征程的基线 3.继续推进新征程,要高效利用子代理加速推进速度
继续
好,可以,继续
好,可以,先提交再继续
```

## Run State

By default, state is persisted next to the script at:

```text
D:\Desktop\codex-autopilot\run-state.json
```

You can override it with:

```powershell
powershell -ExecutionPolicy Bypass -File D:\Desktop\codex-autopilot\codex-autopilot.ps1 -RunStateFile D:\Desktop\codex-autopilot\run-state.json
```

The state file records:

- session id
- working directory
- latest turn
- stop reason
- last exit code
- stall recovery status
- last assistant-message hash and length

If the previous stop reason was `loop_continue`, the next run resumes from the next turn when session id and working directory still match.

## Retry Behavior

Retry transient non-zero `codex exec` exits within the same turn:

```powershell
powershell -ExecutionPolicy Bypass -File D:\Desktop\codex-autopilot\codex-autopilot.ps1 -RetryCount 2 -RetryDelaySeconds 10
```

- Retries do not consume additional turn budget
- Failed retry attempts are logged as `event=exec_retry`
- If retries are exhausted, the run ends with `stop_reason=exec_retry_exhausted`

## Execution Modes

Legacy default:

```powershell
powershell -ExecutionPolicy Bypass -File D:\Desktop\codex-autopilot\codex-autopilot.ps1
```

Explicit full-auto:

```powershell
powershell -ExecutionPolicy Bypass -File D:\Desktop\codex-autopilot\codex-autopilot.ps1 -CodexExecutionMode full-auto
```

Explicit sandbox:

```powershell
powershell -ExecutionPolicy Bypass -File D:\Desktop\codex-autopilot\codex-autopilot.ps1 -CodexExecutionMode sandbox -CodexSandboxMode workspace-write -CodexProfile safe-defaults
```

Supported values:

- `CodexExecutionMode`: `yolo`, `full-auto`, `sandbox`
- `CodexSandboxMode`: `read-only`, `workspace-write`, `danger-full-access`

## Verification

```powershell
Invoke-Pester -Script D:\Desktop\codex-autopilot\tests\codex-autopilot.Tests.ps1 -EnableExit
```
