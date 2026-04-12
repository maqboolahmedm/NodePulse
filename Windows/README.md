# 🪟 NodePulse — Windows Setup Guide

> Status: 🔜 **Coming Soon** — Template available, needs community testing

---

## ⚠️ Important — Before Running Any PowerShell Script

### 1. Allow Script Execution

Windows blocks PowerShell scripts by default.
Open PowerShell **as Administrator** and run:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

Type **Y** and press Enter. You only need to do this once.

---

### 2. Required Network Ports (Outbound)

Make sure these outbound ports are open on your firewall/router:

| Port | Protocol | Purpose |
|---|---|---|
| 443 | HTTPS | Telegram API — required for bot messages |
| 80 | HTTP | DuckDNS updates — required if using DuckDNS |
| 55050–55057 | TCP | DeNet node ports — required for node operation |

> These are **outbound** ports from your PC/VM to the internet.
> Most home networks have these open by default.
> Corporate networks or strict firewalls may block them.

---

### 3. UTF-8 Encoding

Telegram requires UTF-8 encoding for emojis and special characters.
This is already handled at the top of the script:

```powershell
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
```

If emojis show as `????` in Telegram — your system encoding may need adjustment.

---

## ⚠️ Script Status

The current `denet-monitor-win.ps1` was translated from the Linux bash version.
It may contain errors and **has not been fully tested** on Windows.

If you test it and find issues — please open a GitHub issue! 🐛

---

## Files in this folder

| File | Purpose |
|---|---|
| `denet-monitor-win.ps1` | Main monitor — PowerShell script |

---

## Prerequisites

- Windows 10 / 11
- PowerShell 5.1 or later
- DeNet node binary installed
- Telegram bot created via @BotFather
- Port 443 + 80 outbound open

---

## Step 1 — Allow Script Execution

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## Step 2 — Configure

Open `denet-monitor-win.ps1` and fill in:

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
.\denet-monitor-win.ps1
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
   - Arguments: `-ExecutionPolicy Bypass -File "C:\path\to\denet-monitor-win.ps1"`
6. **Conditions** → Uncheck "Start only if on AC power"
7. Click **OK**

---

## 🙏 Help Wanted

If you test and it works → open a GitHub issue ✅
If you find a bug → open a GitHub issue with the error 🐛

Together we make Windows fully supported!
