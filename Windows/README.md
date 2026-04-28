# 🪟 NodePulse — Windows

> Status: 🔜 Coming Soon — Template available, community testing needed.

## Before Running

**Allow PowerShell scripts (run once as Administrator):**
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## Required Ports (Outbound)
| Port | Purpose |
|---|---|
| 443 | Telegram API |
| 80 | DuckDNS updates |
| 55050–55057 | DeNet node ports |

## UTF-8 Encoding
Already included at top of script — required for Telegram emojis:
```powershell
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
```

## Schedule with Task Scheduler
- Program: `powershell.exe`
- Arguments: `-ExecutionPolicy Bypass -File "C:\path\to\nodepulse-monitor.ps1"`
- Trigger: Every 5 minutes

## Help Wanted 🙏
Test and open a GitHub issue with results!
