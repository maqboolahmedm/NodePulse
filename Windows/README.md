# 🪟 NodePulse — Windows Setup Guide

> Status: 🔜 **Coming Soon** — Template available, needs community testing

---

## ⚠️ Important — Before Running Any PowerShell Script

Windows blocks PowerShell scripts by default for security reasons.
You must allow script execution **once** before NodePulse will work.

**Open PowerShell as Administrator** and run:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

When asked to confirm — type **Y** and press Enter.

> 🔒 This only allows scripts you downloaded — it does not disable Windows security.
> You only need to do this once.

---

## ⚠️ Script Status

The current `denet-monitor.ps1` was translated from the Linux bash version.
It may contain errors and **has not been fully tested** on a real Windows setup.

If you test it and find issues — please open a GitHub issue! Your feedback
will help make the Windows version production-ready.

---

## Files in this folder

| File | Purpose |
|---|---|
| `denet-monitor.ps1` | Main monitor — PowerShell script |

---

## Prerequisites

- Windows 10 / 11
- PowerShell 5.1 or later (built into Windows)
- DeNet node binary installed
- Telegram bot created via @BotFather

---

## Step 1 — Allow Script Execution

Open PowerShell **as Administrator**:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## Step 2 — Configure

Open `denet-monitor.ps1` in Notepad or VS Code and fill in:

```powershell
$TELEGRAM_BOT_TOKEN = "your_bot_token"
$TELEGRAM_CHAT_ID   = "your_chat_id"
$DENODE_BIN         = "C:\Program Files\DeNet\denode.exe"
$WALLET_ADDRESS     = "0x..."
$LICENSES           = @("YOUR_LICENSE_1", "YOUR_LICENSE_2")
$DENODE_PASSWORD    = "your_password"
$LOCAL_TIMEZONE     = "W. Europe Standard Time"
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

## Step 3 — Test Manually

```powershell
cd C:\path\to\NodePulse\Windows
.\denet-monitor.ps1
```

Check Telegram for message ✅

---

## Step 4 — Schedule with Task Scheduler

1. Open **Task Scheduler**
2. Click **Create Task**
3. **General** → Name: `DeNet Node Monitor`
4. **Triggers** → New → On a schedule → Repeat every **5 minutes**
5. **Actions** → New:
   - Program: `powershell.exe`
   - Arguments: `-ExecutionPolicy Bypass -File "C:\path\to\denet-monitor.ps1"`
6. **Conditions** → Uncheck "Start only if on AC power"
7. Click **OK**

---

## 🙏 Help Wanted

If you test and it works → open a GitHub issue ✅
If you find a bug → open a GitHub issue with the error 🐛

Together we make Windows fully supported!
