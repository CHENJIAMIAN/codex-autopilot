# codex-autopilot

Windows launcher for resuming Codex sessions, picking a saved session interactively, and continuing turn-by-turn until the user stops it or a safety condition ends the run.

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

If you do not pass `-ResumePrompt`, the script will first show a prompt picker. You can use the up/down arrow keys to choose between the detailed prompt and `继续`, then press Enter to confirm.

```powershell
powershell -ExecutionPolicy Bypass -File D:\Desktop\codex-autopilot\codex-autopilot.ps1
```

## Verification

```powershell
Invoke-Pester -Script D:\Desktop\codex-autopilot\tests\codex-autopilot.Tests.ps1 -EnableExit
```
