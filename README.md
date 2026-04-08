# ⬡ NodePulse — DeNet Node Monitor

> **Community-built monitoring system for [DeNet Datakeeper Nodes](https://denet.pro)**
> Built by a Datakeeper running 6 nodes on Ubuntu VM + QNAP NAS. Praised and shared with the community by the DeNet dev team.

---

## ✨ Features

### 🔍 Auto-Monitor (cron every 5 min)
- Auto-restarts crashed nodes
- **PID tracking** — saves PID every 5 min so history is always accurate
- **Downtime tracking** — records exactly when node went down and offline duration
- **Penalty tracking** — alerts at 5, 8, 10 missed proof cycles
- Disk usage monitoring — alerts at 85%
- Node log error scanning
- Hourly heartbeat with full status
- Daily summary report

### 🤖 Telegram Bot Commands
| Command | Description |
|---|---|
| `/status` | Live status — PID, uptime, restarts, penalties |
| `/restart YOUR_LICENSE` | Restart a specific node |
| `/restartall` | Restart all nodes |
| `/penalties` | Penalty count per node (0–10) |
| `/restarts` | Restart count per node |
| `/history` | Last downtime — when down, offline duration, PID change |
| `/disk` | Storage drive usage |
| `/version` | Current denode binary version |
| `/resetcounts` | Reset restart counters |
| `/help` | All commands |

### 📱 NodePulse Dashboard (PWA + Telegram Mini App)
- **Blockchain status** — ONLINE / PENDING / OFFLINE from Subscan
- **Last on-chain transaction** time per node
- Local process status + uptime
- Disk usage bars
- Restart buttons per node
- Auto-refreshes every 30 seconds
- Works as PWA (phone home screen) and Telegram Mini App

### ⬆️ RC Updater
```bash
denet-update --check     # See available releases
denet-update rc12        # Install rc12
denet-update latest      # Install latest
```

### 🚀 Quick Node Starter
```bash
bash start-nodes.sh      # Start all nodes safely
```

---

## 🔔 Penalty System

DeNet nodes receive **1 penalty per missed proof cycle** (~90 min):
- **5 penalties** → ⚠️ Warning alert
- **8 penalties** → 🚨 Critical alert
- **10 penalties** → 🚫 Removed from pool — auto-restart triggered
- **Successful proof** → ✅ Penalties reset to 0

---

## 📁 File Structure

```
NodePulse/
├── denet-monitor.sh          # Main monitor — Linux (cron every 5 min)
├── denet-bot-listener.sh     # Telegram bot — Linux (systemd service)
├── denet-update.sh           # RC release updater — Linux
├── setup-monitor-linux.sh    # One-click installer — Linux
├── start-nodes.sh            # Simple node starter
├── nodepulse.html            # PWA Dashboard + Telegram Mini App
├── nodepulse-wizard.html     # Setup Wizard — generates configured scripts
├── manifest.json             # PWA manifest
└── docs/
    └── NodePulse_Community_Guide.docx
```

---

## 🚀 Quick Start — Linux (Ubuntu)

### Step 1 — Clone
```bash
git clone https://github.com/maqboolahmedm/NodePulse.git
cd NodePulse
```

### Step 2 — Use the Setup Wizard
Open `nodepulse-wizard.html` in your browser — fill in your details and download pre-configured scripts. No manual editing needed!

### Step 3 — Or configure manually
Edit `denet-monitor.sh` and replace all `YOUR_XXX` placeholders:
```bash
TELEGRAM_BOT_TOKEN="YOUR_TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="YOUR_TELEGRAM_CHAT_ID"
WALLET_ADDRESS="YOUR_WALLET_ADDRESS"
DENODE_PASSWORD="YOUR_NODE_PASSWORD"
LICENSES=(YOUR_LICENSE_1 YOUR_LICENSE_2 ...)
LOCAL_TIMEZONE="YOUR_TIMEZONE"  # e.g. Europe/Berlin, America/New_York, Asia/Manila
```

### Step 4 — Install
```bash
mkdir -p ~/DeNet
cp denet-monitor.sh denet-bot-listener.sh denet-update.sh setup-monitor-linux.sh ~/DeNet/
bash ~/DeNet/setup-monitor-linux.sh
```

### Step 5 — Check Telegram
Bot sends startup message. Send `/help` to confirm ✅

---

## 📱 NodePulse Dashboard Setup

### Option A — Tailscale ⭐ Recommended
No router config needed. Works behind any ISP.

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
tailscale ip   # Note your IP e.g. 100.x.x.x
```

Install Tailscale on phone → open `http://YOUR_TAILSCALE_IP/nodepulse/`

### Option B — Port Forwarding + DuckDNS (Dynamic IP)
Router must support port forwarding. Forward port 80 → VM.
Access via `http://yourname-denet.duckdns.org/nodepulse/`

### Option C — Static Public IP
Forward port 80 → VM. Access via `http://YOUR_STATIC_IP/nodepulse/`

---

## 🌍 Timezone Configuration

Each user sets their own timezone — one line change:
```bash
LOCAL_TIMEZONE="Europe/Berlin"       # Germany
LOCAL_TIMEZONE="America/New_York"    # US East
LOCAL_TIMEZONE="Asia/Manila"         # Philippines
LOCAL_TIMEZONE="Asia/Kolkata"        # India
LOCAL_TIMEZONE="America/Los_Angeles" # US West
LOCAL_TIMEZONE="Asia/Singapore"      # Singapore
```

All Telegram messages show UTC + your local time automatically.

---

## 🖥️ Platform Support

| Platform | Status | Notes |
|---|---|---|
| 🐧 Linux (Ubuntu 20.04 / 22.04) | ✅ **Fully Supported** | Tested and production-ready |
| 🪟 Windows 10/11 | 🔜 **Coming Soon** | Template available — needs testing |
| 🍎 macOS 12+ | 🔜 **Coming Soon** | Template available — needs testing |

> Linux is the recommended platform for DeNet nodes.

---

## ⚠️ Known Limitations

- **Process ≠ Online** — monitor checks if process is running, not if proofs are being submitted on-chain
- **Blockchain status** — NodePulse v2 queries Subscan for on-chain status — requires wallet address
- **Penalty detection** — based on log scanning — accuracy depends on log format of your RC version

---

## 🗺️ Roadmap

### ✅ v1.0
- Auto-restart, PID tracking, downtime history, Telegram bot, NodePulse PWA, RC updater

### ✅ v2.0 (Current)
- Penalty tracking and alerts
- Blockchain status via Subscan
- Last on-chain transaction monitoring
- Configurable timezone (not hardcoded to India)
- PID saved every 5 min — accurate history after reboots
- /penalties Telegram command
- IST removed — each user sets own timezone

### 🔜 v3.0 (Planned)
- Pool number monitoring
- RPC health check
- Smart restart — only if both process AND blockchain confirm down
- Full Windows & macOS support
- Multi-VM support
- AI-powered log analysis

---

## 📖 Documentation

See [docs/NodePulse_Community_Guide.docx](docs/NodePulse_Community_Guide.docx) for full setup guide.

---

## 🤝 Contributing

Built for the DeNet Datakeeper community. Improvements welcome!
- Open an issue for bugs
- Submit a PR for improvements
- Share in the [DeNet Discord](https://discord.gg/denet)

---

## 📄 License

MIT — free to use, modify, and share.

---

*Built with ❤️ by a DeNet Datakeeper — 6 nodes, Ubuntu VM + QNAP NAS*
