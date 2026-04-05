# ⬡ NodePulse — DeNet Node Monitor

A complete monitoring and management system for [DeNet Datakeeper Nodes](https://denet.pro). Built by a community member running 6 nodes on Ubuntu VM + QNAP NAS.

![NodePulse Dashboard](docs/screenshot.png)

---

## ✨ Features

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
| `/disk` | Storage drive usage |
| `/version` | Current denode binary version |
| `/resetcounts` | Reset restart counters |
| `/help` | All commands |

### 📱 NodePulse Dashboard
- Live PWA (Progressive Web App) — install on phone home screen
- Works as **Telegram Mini App** — open inside your bot chat
- Shows all nodes: PID, uptime, restart count, disk usage
- ⚠️ Silent restart alerts highlighted
- Restart buttons per node
- Auto-refreshes every 30 seconds

### ⬆️ RC Updater
```bash
denet-update --check     # See available releases
denet-update rc12        # Install specific RC
denet-update latest      # Install latest release
```
- Auto-detects Linux AMD64 binary
- Backs up old binary before replacing
- Stops nodes, installs, notifies Telegram
- Shows RC12+ checklist automatically

---

## 📁 File Structure

```
NodePulse/
├── denet-monitor.sh          # Main monitor — cron every 5 min
├── denet-bot-listener.sh     # Telegram bot — systemd service
├── denet-update.sh           # RC release updater
├── setup-monitor-linux.sh    # One-click installer (Linux)
├── nodepulse.html            # PWA Dashboard + Telegram Mini App
├── manifest.json             # PWA manifest
└── docs/
    └── NodePulse_Community_Guide.docx   # Full setup guide
```

---

## 🚀 Quick Start — Linux (Ubuntu)

### Prerequisites
- Ubuntu 20.04 / 22.04
- DeNet node binary installed (`/usr/bin/denode`)
- Telegram bot created via [@BotFather](https://t.me/BotFather)
- `manager_config.yaml` configured with your licenses

### Step 1 — Clone the repo
```bash
git clone https://github.com/maqboolahmedm/NodePulse.git
cd NodePulse
```

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
```bash
mkdir -p ~/DeNet
cp denet-monitor.sh denet-bot-listener.sh denet-update.sh setup-monitor-linux.sh ~/DeNet/
bash ~/DeNet/setup-monitor-linux.sh
```

### Step 4 — Check Telegram
The bot will send a startup message. Send `/help` to see all commands. ✅

---

## 📱 NodePulse Dashboard Setup

### Option A — Tailscale (Recommended — no router config needed)

1. Install Tailscale on your VM:
```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
tailscale ip   # Note your IP e.g. 100.x.x.x
```

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

---

## 🖥️ Platform Support

| Platform | Status | Notes |
|---|---|---|
| 🐧 Linux (Ubuntu 20.04 / 22.04) | ✅ **Fully Supported** | Tested and production-ready |
| 🪟 Windows | 🔜 **Coming Soon** | PowerShell templates available but not fully tested |
| 🍎 macOS | 🔜 **Coming Soon** | launchd templates available but not fully tested |

> **Linux is the recommended platform.** DeNet nodes are designed to run on Linux servers/VMs. Windows and macOS support is planned for future releases.

---

## 📖 Full Documentation

See [docs/NodePulse_Community_Guide.docx](docs/NodePulse_Community_Guide.docx) for the complete setup guide including troubleshooting, credentials setup, and RC upgrade instructions.

---

## 🤝 Contributing

Built for the DeNet Datakeeper community. If you improve it, please share back!

- Open an issue for bugs
- Submit a PR for improvements
- Share in the [DeNet Discord](https://discord.gg/denet)

---

## 📄 License

MIT License — free to use, modify, and share.

---

*Built with ❤️ by a DeNet Datakeeper — running 6 nodes on Ubuntu VM + QNAP NAS*
