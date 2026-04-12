# 🍎 NodePulse — macOS Setup Guide

> Status: 🔜 Coming Soon — Template available, needs community testing

---

## Files in this folder

| File | Purpose |
|---|---|
| `denet-monitor-macos.sh` | Main monitor — bash script |

---

## Prerequisites

- macOS 12 (Monterey) or later
- DeNet node binary installed at `/usr/local/bin/denode`
- Telegram bot created via @BotFather
- Homebrew recommended: `brew install curl`

---

## Step 1 — Configure

Open `denet-monitor-macos.sh` and fill in:

```bash
TELEGRAM_BOT_TOKEN="your_bot_token"
TELEGRAM_CHAT_ID="your_chat_id"
DENODE_BIN="/usr/local/bin/denode"
WALLET_ADDRESS="0x..."
LICENSES=(1072 1864 1865)
DENODE_PASSWORD="your_password"
LOCAL_TIMEZONE="America/New_York"   # Your timezone
```

### Timezone Examples
```bash
LOCAL_TIMEZONE="America/New_York"    # US East
LOCAL_TIMEZONE="America/Los_Angeles" # US West
LOCAL_TIMEZONE="Europe/Berlin"       # Germany
LOCAL_TIMEZONE="Asia/Kolkata"        # India
LOCAL_TIMEZONE="Asia/Manila"         # Philippines
LOCAL_TIMEZONE="Asia/Singapore"      # Singapore
LOCAL_TIMEZONE="UTC"                 # Universal
```

---

## Step 2 — Make Executable

```bash
chmod +x denet-monitor-macos.sh
```

---

## Step 3 — Test Manually

```bash
export DENODE_PASSWORD="your_password"
bash denet-monitor-macos.sh
```

Check Telegram for heartbeat ✅

---

## Step 4 — Schedule with launchd

Create a plist file:

```bash
nano ~/Library/LaunchAgents/com.denet.monitor.plist
```

Paste this content:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.denet.monitor</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/Users/YOUR_USERNAME/DeNet/denet-monitor-macos.sh</string>
  </array>
  <key>StartInterval</key>
  <integer>300</integer>
  <key>EnvironmentVariables</key>
  <dict>
    <key>DENODE_PASSWORD</key>
    <string>your_password</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/Users/YOUR_USERNAME/.denode/monitor.log</string>
  <key>StandardErrorPath</key>
  <string>/Users/YOUR_USERNAME/.denode/monitor-error.log</string>
</dict>
</plist>
```

Load it:
```bash
launchctl load ~/Library/LaunchAgents/com.denet.monitor.plist
```

Verify:
```bash
launchctl list | grep denet
```

---

## ⚠️ Note

macOS support is a community template. If you test it successfully, please open an issue on GitHub with your results so we can mark it as fully supported!
