# 🐧 NodePulse — Linux Setup Guide

> Full support — tested and production-ready on Ubuntu 20.04 / 22.04

---

## Files in this folder

| File | Purpose | How it runs |
|---|---|---|
| `denet-monitor-lsw.sh` | Main monitor — auto-restart, PID tracking, penalty alerts | cron every 5 min |
| `denet-bot-listener-lsw.sh` | Telegram bot — /restart, /status, /penalties, /history | systemd service |
| `denet-update-lsw.sh` | RC release updater | Run manually |
| `setup-monitor-lsw.sh` | One-click installer | Run once |
| `start-nodes.sh` | Simple node starter | Run manually |

---

## Quick Start

### Step 1 — Configure your credentials
Edit `denet-monitor-lsw.sh` and `denet-bot-listener-lsw.sh`:

```bash
TELEGRAM_BOT_TOKEN="your_bot_token"
TELEGRAM_CHAT_ID="your_chat_id"
WALLET_ADDRESS="0x..."
DENODE_PASSWORD="your_password"
LICENSES=(YOUR_LICENSE_1 YOUR_LICENSE_2 YOUR_LICENSE_3)  # your license numbers
LOCAL_TIMEZONE="Europe/Berlin"    # your timezone
```

### Step 2 — Install
```bash
mkdir -p ~/DeNet
cp denet-monitor-lsw.sh denet-bot-listener-lsw.sh denet-update-lsw.sh \
   setup-monitor-lsw.sh start-nodes.sh ~/DeNet/
bash ~/DeNet/setup-monitor-lsw.sh
```

### Step 3 — Verify
```bash
crontab -l | grep denet            # Should show cron job
sudo systemctl status denet-bot    # Should show active
```

Check Telegram — bot sends startup message ✅

---

## Telegram Commands

| Command | Description |
|---|---|
| `/status` | Live status with PID tracking |
| `/restart YOUR_LICENSE` | Restart specific node |
| `/restartall` | Restart all nodes |
| `/penalties` | Penalty count per node (0–10) |
| `/restarts` | Restart count per node |
| `/history` | Last downtime per node |
| `/disk` | Storage usage |
| `/version` | denode binary version |
| `/resetcounts` | Reset restart counters |

---

## RC Updater

```bash
# Install as system command
sudo cp ~/DeNet/denet-update-lsw.sh /usr/local/bin/denet-update
sudo chmod +x /usr/local/bin/denet-update

# Usage
denet-update --check    # List releases
denet-update rc13       # Install rc13
denet-update latest     # Install latest
```

---

## Timezones

Set `LOCAL_TIMEZONE` in the scripts:

```bash
LOCAL_TIMEZONE="Asia/Kolkata"        # India
LOCAL_TIMEZONE="Europe/Berlin"       # Germany
LOCAL_TIMEZONE="America/New_York"    # US East
LOCAL_TIMEZONE="Asia/Manila"         # Philippines
LOCAL_TIMEZONE="America/Los_Angeles" # US West
LOCAL_TIMEZONE="Asia/Singapore"      # Singapore
LOCAL_TIMEZONE="UTC"                 # Universal
```

All Telegram messages show UTC + your local time.
