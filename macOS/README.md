# NodePulse — macOS

Monitor your DeNet Datakeeper nodes on macOS using bash and launchd.

> **Note:** The macOS version currently provides core node monitoring and Telegram alerts.
> Full bot control, Guard health scoring, and the proxy dashboard are Linux features.
> Community contributions to expand macOS support are welcome.

---

## What's Included

| File | Purpose |
|---|---|
| `nodepulse-monitor.sh` | Node health monitor + Telegram alerts |
| `nodepulse-clean-cache.sh` | RAM / temp cache cleaner (no Telegram, no alerts) |

---

## Requirements

- macOS 11 (Big Sur) or newer
- bash (pre-installed on macOS)
- `curl` (pre-installed on macOS)
- `jq` — install via Homebrew
- DeNet Datakeeper installed and running
- Telegram bot token (get one from [@BotFather](https://t.me/BotFather))
- Your Telegram Chat ID

---

## Install Dependencies

Install Homebrew if you don't have it:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Install jq:
```bash
brew install jq
```

---

## Installation

### Step 1 — Clone the Repo

```bash
git clone https://github.com/maqboolahmedm/NodePulse.git ~/NodePulse
cp ~/NodePulse/macOS/nodepulse-monitor.sh ~/NodePulse/
chmod +x ~/NodePulse/nodepulse-monitor.sh
```

### Step 2 — Configure

Open the script and edit the variables at the top:

```bash
nano ~/NodePulse/nodepulse-monitor.sh
```

```bash
BOT_TOKEN="YOUR_BOT_TOKEN"
CHAT_ID="YOUR_CHAT_ID"
WALLET="0xYOUR_WALLET"
PASSWORD="yourpassword"
LICENSES="1072 1864 1865"
STORAGE_PATH="$HOME/DeNet/Storage"
TIMEZONE="America/New_York"
```

Save and close.

### Step 3 — Test

Run manually to confirm it works:
```bash
bash ~/NodePulse/nodepulse-monitor.sh
```

You should receive a Telegram status message.

### Step 4 — Schedule with launchd

Create a launchd plist to run the monitor every 5 minutes:

```bash
cat > ~/Library/LaunchAgents/com.nodepulse.monitor.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.nodepulse.monitor</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Users/YOUR_USERNAME/NodePulse/nodepulse-monitor.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>300</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/Users/YOUR_USERNAME/.nodepulse/monitor.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/YOUR_USERNAME/.nodepulse/monitor.log</string>
</dict>
</plist>
EOF
```

> Replace `YOUR_USERNAME` with your actual macOS username.

Load it:
```bash
mkdir -p ~/.nodepulse
launchctl load ~/Library/LaunchAgents/com.nodepulse.monitor.plist
```

Verify it loaded:
```bash
launchctl list | grep nodepulse
```

---

## Managing the Monitor

```bash
# Stop
launchctl unload ~/Library/LaunchAgents/com.nodepulse.monitor.plist

# Start
launchctl load ~/Library/LaunchAgents/com.nodepulse.monitor.plist

# View logs
tail -f ~/.nodepulse/monitor.log
```

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

**`jq: command not found`:**
```bash
brew install jq
```

**No Telegram message received:**
- Verify `BOT_TOKEN` and `CHAT_ID` are correct
- Test: `https://api.telegram.org/bot<TOKEN>/getMe`

**launchd job not running:**
```bash
launchctl list | grep nodepulse
# If missing, reload:
launchctl load ~/Library/LaunchAgents/com.nodepulse.monitor.plist
```

**Permission denied on script:**
```bash
chmod +x ~/NodePulse/nodepulse-monitor.sh
```

---

## Cache Cleaner

`nodepulse-clean-cache.sh` clears system and browser caches to free up disk space. No Telegram messages, no prompts, no external dependencies.

**What it cleans:**
- System: `/tmp`, `/var/folders`, `/Library/Caches`, `/Library/Logs` (requires sudo)
- User: `~/Library/Caches`, `~/Library/Logs`, `~/Library/Saved Application State`, `~/Library/Cookies`
- Chrome, Safari, Edge, Firefox (cache2), Microsoft Teams
- Trash (`~/.Trash`)

**Output:** prints each path cleaned and shows total elapsed time on completion.

Run it manually:
```bash
bash ~/NodePulse/nodepulse-clean-cache.sh
```

> The script uses `sudo` internally to clean `/Library/Logs`. You may be prompted for your password on first run.

Schedule it via launchd to run daily — same process as the monitor plist, just set `StartInterval` to `86400` (24 hours).

> **Known limitation:** Firefox cache and `/var/folders` use glob patterns (`*/`) inside the `clean_dir` function. Because the function receives the glob as a quoted string, it may not expand correctly on all macOS versions. These paths are silently skipped if they don't resolve — all other paths clean normally.

---

## Contributing

macOS support is maintained by the community. If you improve the script or add features like Guard health scoring or launchd auto-setup, pull requests are very welcome.

---

*Part of the NodePulse community toolkit — github.com/maqboolahmedm/NodePulse*
