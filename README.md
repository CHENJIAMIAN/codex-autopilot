# codex-autopilot

Windows launcher for resuming Codex sessions, picking a saved session interactively, and looping until the task is actually complete.

## Files

- `codex-autopilot.ps1`: main script
- `codex-autopilot.cmd`: double-clickable launcher
- `tests/codex-autopilot.Tests.ps1`: Pester tests

## Usage

Run the launcher:

```powershell
D:\Desktop\codex-autopilot\codex-autopilot.cmd
```

Or run the PowerShell script directly:

```powershell
powershell -ExecutionPolicy Bypass -File D:\Desktop\codex-autopilot\codex-autopilot.ps1
```

## Verification

```powershell
Invoke-Pester -Script D:\Desktop\codex-autopilot\tests\codex-autopilot.Tests.ps1 -EnableExit
```
