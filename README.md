# ⬡ NodePulse — DeNet Node Monitor

<<<<<<< HEAD
> **Community-built monitoring system for [DeNet Datakeeper Nodes](https://denet.pro)**
> Built by a Datakeeper running 6 nodes on Ubuntu VM + QNAP NAS. Praised and shared with the community by the DeNet dev team.
=======
A complete monitoring and management system for [DeNet Datakeeper Nodes](https://denet.pro). Built by a community member running 6 nodes on Ubuntu VM + QNAP NAS.

![NodePulse Dashboard](docs/screenshot.png)
>>>>>>> ea719db645f5f3824483919fc75481022eac4da8

---

## ✨ Features

<<<<<<< HEAD
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
| `/restart 1072` | Restart a specific node |
| `/restartall` | Restart all nodes |
| `/penalties` | Penalty count per node (0–10) |
| `/restarts` | Restart count per node |
| `/history` | Last downtime — when down, offline duration, PID change |
=======
### 🔍 Auto-Monitor (runs every 5 minutes via cron)
- Automatically detects and restarts crashed nodes
- **PID change detection** — catches silent restarts you'd never know about
- **Downtime tracking** — records exactly when a node went down and how long it was offline
- Disk usage monitoring with alerts at 85%
- Node log error scanning — roothash mismatch, RPC timeouts, unlock errors
- Hourly heartbeat to Telegram with full node status
- Daily summary report at 8:00 AM

### 🤖 Telegram Bot (always-on systemd service)
| Command | Description |
|---|---|
| `/status` | Live status with PID change detection |
| `/restart 1072` | Restart a specific node |
| `/restartall` | Restart all nodes |
| `/restarts` | Restart count per node |
| `/history` | Last downtime event per node |
>>>>>>> ea719db645f5f3824483919fc75481022eac4da8
| `/disk` | Storage drive usage |
| `/version` | Current denode binary version |
| `/resetcounts` | Reset restart counters |
| `/help` | All commands |

<<<<<<< HEAD
### 📱 NodePulse Dashboard (PWA + Telegram Mini App)
- **Blockchain status** — ONLINE / PENDING / OFFLINE from Subscan
- **Last on-chain transaction** time per node
- Local process status + uptime
- Disk usage bars
- Restart buttons per node
- Auto-refreshes every 30 seconds
- Works as PWA (phone home screen) and Telegram Mini App
=======
### 📱 NodePulse Dashboard
- Live PWA (Progressive Web App) — install on phone home screen
- Works as **Telegram Mini App** — open inside your bot chat
- Shows all nodes: PID, uptime, restart count, disk usage
- ⚠️ Silent restart alerts highlighted
- Restart buttons per node
- Auto-refreshes every 30 seconds
>>>>>>> ea719db645f5f3824483919fc75481022eac4da8

### ⬆️ RC Updater
```bash
denet-update --check     # See available releases
<<<<<<< HEAD
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
=======
denet-update rc12        # Install specific RC
denet-update latest      # Install latest release
```
- Auto-detects Linux AMD64 binary
- Backs up old binary before replacing
- Stops nodes, installs, notifies Telegram
- Shows RC12+ checklist automatically
>>>>>>> ea719db645f5f3824483919fc75481022eac4da8

---

## 📁 File Structure

```
NodePulse/
<<<<<<< HEAD
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
=======
├── denet-monitor.sh          # Main monitor — cron every 5 min
├── denet-bot-listener.sh     # Telegram bot — systemd service
├── denet-update.sh           # RC release updater
├── setup-monitor-linux.sh    # One-click installer (Linux)
├── nodepulse.html            # PWA Dashboard + Telegram Mini App
├── manifest.json             # PWA manifest
└── docs/
    └── NodePulse_Community_Guide.docx   # Full setup guide
>>>>>>> ea719db645f5f3824483919fc75481022eac4da8
```

---

## 🚀 Quick Start — Linux (Ubuntu)

<<<<<<< HEAD
### Step 1 — Clone
=======
### Prerequisites
- Ubuntu 20.04 / 22.04
- DeNet node binary installed (`/usr/bin/denode`)
- Telegram bot created via [@BotFather](https://t.me/BotFather)
- `manager_config.yaml` configured with your licenses

### Step 1 — Clone the repo
>>>>>>> ea719db645f5f3824483919fc75481022eac4da8
```bash
git clone https://github.com/maqboolahmedm/NodePulse.git
cd NodePulse
```

<<<<<<< HEAD
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
=======
### Step 2 — Configure your credentials
Edit `denet-monitor.sh` and replace all `YOUR_XXX` placeholders:
```bash
nano denet-monitor.sh
```

Key values to fill in:
```bash
TELEGRAM_BOT_TOKEN="YOUR_TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="YOUR_TELEGRAM_CHAT_ID"
WALLET_ADDRESS="YOUR_WALLET_ADDRESS"
LICENSES=(YOUR_LICENSE_1 YOUR_LICENSE_2 ...)
DENODE_PASSWORD="YOUR_NODE_PASSWORD"
```

Do the same for `denet-bot-listener.sh`.

### Step 3 — Copy and install
>>>>>>> ea719db645f5f3824483919fc75481022eac4da8
```bash
mkdir -p ~/DeNet
cp denet-monitor.sh denet-bot-listener.sh denet-update.sh setup-monitor-linux.sh ~/DeNet/
bash ~/DeNet/setup-monitor-linux.sh
```

<<<<<<< HEAD
### Step 5 — Check Telegram
Bot sends startup message. Send `/help` to confirm ✅
=======
### Step 4 — Check Telegram
The bot will send a startup message. Send `/help` to see all commands. ✅
>>>>>>> ea719db645f5f3824483919fc75481022eac4da8

---

## 📱 NodePulse Dashboard Setup

<<<<<<< HEAD
### Option A — Tailscale ⭐ Recommended
No router config needed. Works behind any ISP.

=======
### Option A — Tailscale (Recommended — no router config needed)

1. Install Tailscale on your VM:
>>>>>>> ea719db645f5f3824483919fc75481022eac4da8
```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
tailscale ip   # Note your IP e.g. 100.x.x.x
```

<<<<<<< HEAD
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
=======
2. Install [Tailscale app](https://tailscale.com/download) on your phone

3. Install nginx and deploy:
```bash
sudo apt install nginx -y
sudo mkdir -p /var/www/html/nodepulse
sudo cp nodepulse.html /var/www/html/nodepulse/index.html
sudo cp manifest.json /var/www/html/nodepulse/manifest.json
sudo chown -R $USER:$USER /var/www/html/nodepulse/
sudo systemctl enable nginx && sudo systemctl start nginx
```

4. Open on phone: `http://YOUR_TAILSCALE_IP/nodepulse/`

5. Enter your Status URL, Bot Token, Chat ID → **Connect**

6. Tap ⋮ → **Add to Home Screen** to install as PWA

---

### Option B — Port Forwarding + DuckDNS (Dynamic Public IP)

Use this if your ISP gives you a dynamic public IP and your router supports port forwarding.

1. **Create DuckDNS account** at [duckdns.org](https://www.duckdns.org)
   - Create a domain e.g. `yourname-denet.duckdns.org`
   - Copy your token

2. **Add DuckDNS updater to cron:**
```bash
# Add to crontab -e
*/5 * * * * curl -s "https://www.duckdns.org/update?domains=YOUR_DOMAIN&token=YOUR_TOKEN&ip=" > /dev/null
```

3. **Configure port forwarding on your router:**
   - Forward port **80** → VM IP (for NodePulse)
   - Forward ports **55050-55057** → VM IP (for DeNet nodes)

4. **Install nginx** (same as Option A steps 3 above)

5. Open on phone: `http://yourname-denet.duckdns.org/nodepulse/`

> ⚠️ Add nginx password protection before making publicly accessible!

---

### Option C — Static Public IP

Use this if your ISP provides a static public IP.

1. Same as Option B — but skip DuckDNS
2. Use your static IP directly in nginx and nodepulse config
3. Consider adding a domain name for easier access

---

## 📲 Telegram Mini App Setup

Add NodePulse as a button inside your Telegram bot:

1. Open [@BotFather](https://t.me/BotFather)
2. `/mybots` → select your bot
3. **Bot Settings** → **Menu Button**
4. Set URL: `http://YOUR_IP_OR_DOMAIN/nodepulse/`
5. Set button text: `NodePulse Dashboard`

Now a **NodePulse** button appears in your bot chat — tap to open the dashboard inside Telegram!

---

## 🔧 How It Works

```
┌─────────────────────────────────────────────────┐
│  denet-monitor.sh (cron every 5 min)            │
│  ├── Check all node PIDs                        │
│  ├── Compare with saved PIDs                    │
│  ├── Detect silent restarts                     │
│  ├── Auto-restart crashed nodes                 │
│  ├── Record downtime timestamps                 │
│  ├── Check disk usage                           │
│  ├── Scan node logs for errors                  │
│  ├── Send hourly heartbeat to Telegram          │
│  └── Write status.json → nginx → NodePulse     │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│  denet-bot-listener.sh (systemd, always on)     │
│  ├── Long-polls Telegram every 30s              │
│  ├── Handles /restart, /status, /history etc.  │
│  └── Reads shared state files from monitor     │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│  NodePulse Dashboard (PWA / Telegram Mini App)  │
│  ├── Reads status.json via nginx                │
│  ├── Sends commands via Telegram Bot API        │
│  └── Auto-refreshes every 30 seconds           │
└─────────────────────────────────────────────────┘
```

---

## 📊 State Files

| File | Contents |
|---|---|
| `~/.denode/.node_pids` | Last known PID per node |
| `~/.denode/.node_last_seen` | Last confirmed alive timestamp |
| `~/.denode/.node_downtime_log` | Full downtime history |
| `~/.denode/.restart_counts` | All-time restart count per node |
| `/var/www/html/nodepulse/status.json` | Live dashboard data |

---

## ⚠️ Known Limitations

> Feedback from the DeNet community:

- **Process ≠ Online** — NodePulse checks if the node *process* is running, but a running process doesn't mean the node is actively submitting proofs on-chain. A node can be running locally but offline on the blockchain.
- **No blockchain status** — We don't yet query on-chain data to verify the node is actually ONLINE/PENDING/OFFLINE
- **No pool monitoring** — Pool number not tracked yet
- **No connectivity check** — No ping/RPC health check yet

These are being worked on in **v2.0**. See Roadmap below.

---

## 🗺️ Roadmap

### ✅ v1.0 (Current)
- Auto-restart crashed nodes
- PID change detection — catches silent restarts
- Downtime tracking
- Telegram bot with /restart, /status, /history
- NodePulse PWA dashboard
- RC release updater

### 🔜 v2.0 (In Progress)
- **Blockchain status** — Query nodecheck.old-guys.de for real ONLINE/PENDING/OFFLINE per node
- **Transaction monitoring** — Detect if node stopped sending proofs (last tx time)
- **Pool number** — Show which pool each node is in
- **RPC/connectivity health check** — Ping RPC endpoint before declaring node healthy
- **Smart restart** — Only restart if both process AND blockchain confirm node is down
- **Windows & macOS** — Full tested support

### 💡 v3.0 (Planned)
- AI-powered log analysis
- Predictive alerts before node goes down
- Multi-VM support

---

- Restart is free while node is in pool — minimize unnecessary restarts
- Never delete files in your storage path — contains proof history
- Always export `DENODE_PASSWORD` before manual restarts
- The `--port`, `--rpc`, `--storage` flags don't work in rc11/rc12 — denode reads from `manager_config.yaml`
>>>>>>> ea719db645f5f3824483919fc75481022eac4da8

---

## 🖥️ Platform Support

| Platform | Status | Notes |
|---|---|---|
| 🐧 Linux (Ubuntu 20.04 / 22.04) | ✅ **Fully Supported** | Tested and production-ready |
<<<<<<< HEAD
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
=======
| 🪟 Windows | 🔜 **Coming Soon** | PowerShell templates available but not fully tested |
| 🍎 macOS | 🔜 **Coming Soon** | launchd templates available but not fully tested |

> **Linux is the recommended platform.** DeNet nodes are designed to run on Linux servers/VMs. Windows and macOS support is planned for future releases.

---

## 📖 Full Documentation

See [docs/NodePulse_Community_Guide.docx](docs/NodePulse_Community_Guide.docx) for the complete setup guide including troubleshooting, credentials setup, and RC upgrade instructions.
>>>>>>> ea719db645f5f3824483919fc75481022eac4da8

---

## 🤝 Contributing

<<<<<<< HEAD
Built for the DeNet Datakeeper community. Improvements welcome!
=======
Built for the DeNet Datakeeper community. If you improve it, please share back!

>>>>>>> ea719db645f5f3824483919fc75481022eac4da8
- Open an issue for bugs
- Submit a PR for improvements
- Share in the [DeNet Discord](https://discord.gg/denet)

---

## 📄 License

<<<<<<< HEAD
MIT — free to use, modify, and share.

---

*Built with ❤️ by a DeNet Datakeeper — 6 nodes, Ubuntu VM + QNAP NAS*
=======
MIT License — free to use, modify, and share.

---

*Built with ❤️ by a DeNet Datakeeper — running 6 nodes on Ubuntu VM + QNAP NAS*
>>>>>>> ea719db645f5f3824483919fc75481022eac4da8
