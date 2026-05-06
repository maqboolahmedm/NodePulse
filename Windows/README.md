# NodePulse — Windows

Monitor your DeNet Datakeeper nodes on Windows using PowerShell.

> **Note:** The Windows version currently provides core node monitoring and Telegram alerts.
> Full bot control, Guard health scoring, and the proxy dashboard are Linux features.
> Community contributions to expand Windows support are welcome.

---

## What's Included

| File | Purpose |
|---|---|
| `nodepulse-monitor.ps1` | Node health monitor + Telegram alerts |
| `nodepulse-clean-cache.ps1` | RAM / temp cache cleaner (no Telegram, no alerts) |

---

## Requirements

- Windows 10 / Windows 11
- PowerShell 5.1+ (built into Windows — no install needed)
- DeNet Datakeeper installed and running
- Telegram bot token (get one from [@BotFather](https://t.me/BotFather))
- Your Telegram Chat ID

---

## Installation

### Step 1 — Download

Download or clone the repository:
```
https://github.com/maqboolahmedm/NodePulse
```

Copy `nodepulse-monitor.ps1` to a folder of your choice, for example:
```
C:\NodePulse\nodepulse-monitor.ps1
```

### Step 2 — Configure

Open `nodepulse-monitor.ps1` in Notepad or any text editor.

Edit the variables at the top of the file:

```powershell
$BOT_TOKEN    = "YOUR_BOT_TOKEN"
$CHAT_ID      = "YOUR_CHAT_ID"
$WALLET       = "0xYOUR_WALLET"
$LICENSES     = @("1072", "1864", "1865")    # your license IDs
$STORAGE_PATH = "C:\DeNet\Storage"
```

Save the file.

### Step 3 — Allow Script Execution

Open PowerShell as Administrator and run:
```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Step 4 — Test

Run the script manually to verify it works:
```powershell
cd C:\NodePulse
.\nodepulse-monitor.ps1
```

If configured correctly, you will receive a Telegram message with your node status.

### Step 5 — Schedule with Task Scheduler

To run the monitor automatically every 5 minutes:

1. Open **Task Scheduler** (search in Start menu)
2. Click **Create Basic Task**
3. Name it: `NodePulse Monitor`
4. Trigger: **Daily** → then set to repeat every **5 minutes**
5. Action: **Start a program**
   - Program: `powershell.exe`
   - Arguments: `-ExecutionPolicy Bypass -File "C:\NodePulse\nodepulse-monitor.ps1"`
6. Click **Finish**

---

## Telegram Alerts

The Windows monitor sends Telegram alerts when:

- A node process is not found running
- A node has not produced a proof within the expected window
- A node has accumulated penalties

---

## DeNet Node Cycle Reference

```
FillRoothash   → ~15 min
HoldData       → ~60 min  (no activity — this is normal)
CollectProofs  → ~15 min
Total cycle    → ~90 min

1 penalty per missed cycle
10 penalties → pool removal
Restart is FREE while still in pool
Successful proof resets penalties to 0
```

---

## Troubleshooting

**Script won't run — execution policy error:**
```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**No Telegram message received:**
- Check your `BOT_TOKEN` and `CHAT_ID` are correct
- Test your bot token: open `https://api.telegram.org/bot<YOUR_TOKEN>/getMe` in a browser

**Node not detected:**
- Check the DeNet process name matches what's running
- Open Task Manager and verify the denode process is active

---

## Cache Cleaner

`nodepulse-clean-cache.ps1` clears system and browser caches to free up disk space. No Telegram messages, no prompts, no external dependencies.

**What it cleans:**
- System: `C:\Windows\Temp`, Recycle Bin, `C:\Windows\Prefetch`
- User: `%TEMP%`, `AppData\Local\Temp`, IE/Edge INetCache, INetCookies, WER crash reports
- Chrome: cache, cookies, history
- Edge: cache, cookies, history
- Firefox: cache2, thumbnails
- Teams: cache, blob_storage, databases, GPU cache

**Output:** prints each step and shows total elapsed time on completion.

Run it manually:
```powershell
.\nodepulse-clean-cache.ps1
```

> Run as **Administrator** to clean system folders (`C:\Windows\Temp`, Prefetch, Recycle Bin). Without admin rights, user-level caches are still cleaned successfully.

Schedule in Task Scheduler to run weekly — same process as the monitor, just set the interval to daily or weekly.

---

## Contributing

Windows support is maintained by the community. If you improve the PowerShell script or add features (bot commands, Task Scheduler auto-setup, Guard scoring), pull requests are very welcome.

---

*Part of the NodePulse community toolkit — github.com/maqboolahmedm/NodePulse*
