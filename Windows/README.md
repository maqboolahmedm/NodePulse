# 🪟 NodePulse — Windows Setup Guide

> Status: 🔜 Coming Soon — Template available, needs community testing

---

## Files in this folder

| File | Purpose |
|---|---|
| `denet-monitor.ps1` | Main monitor — PowerShell script |

---

## Prerequisites

- Windows 10 / 11
- PowerShell 5.1 or later
- DeNet node binary installed
- Telegram bot created via @BotFather

---

## Step 1 — Configure

Open `denet-monitor.ps1` in Notepad or VS Code and fill in:

```powershell
$TELEGRAM_BOT_TOKEN = "your_bot_token"
$TELEGRAM_CHAT_ID   = "your_chat_id"
$DENODE_BIN         = "C:\Program Files\DeNet\denode.exe"
$WALLET_ADDRESS     = "0x..."
$LICENSES           = @("1072", "1864", "1865")
$DENODE_PASSWORD    = "your_password"
$LOCAL_TIMEZONE     = "W. Europe Standard Time"  # Your Windows timezone
```

### Windows Timezone Names
| Region | Timezone String |
|---|---|
| India | `India Standard Time` |
| Germany | `W. Europe Standard Time` |
| US East | `Eastern Standard Time` |
| Philippines | `Singapore Standard Time` |
| US West | `Pacific Standard Time` |
| UTC | `UTC` |

Full list: https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/default-time-zones

---

## Step 2 — Allow PowerShell Scripts

Open PowerShell as Administrator:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## Step 3 — Test Manually

```powershell
cd C:\path\to\NodePulse\windows
.\denet-monitor.ps1
```

Check Telegram for heartbeat message ✅

---

## Step 4 — Schedule with Task Scheduler

1. Open **Task Scheduler**
2. Click **Create Task**
3. **General** tab: Name it `DeNet Node Monitor`
4. **Triggers** tab: New → **On a schedule** → Repeat every **5 minutes**
5. **Actions** tab: New →
   - Program: `powershell.exe`
   - Arguments: `-ExecutionPolicy Bypass -File "C:\path\to\denet-monitor.ps1"`
6. **Conditions** tab: Uncheck "Start only if on AC power"
7. Click **OK**

---

## ⚠️ Note

Windows support is a community template. If you test it successfully, please open an issue on GitHub with your results so we can mark it as fully supported!
