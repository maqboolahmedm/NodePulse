# ⬡ NodePulse — DeNet Node Monitor

> **Community-built monitoring system for [DeNet Datakeeper Nodes](https://denet.pro)**
> Built by a Datakeeper running 6 nodes on Ubuntu VM + QNAP NAS. Praised and shared with the community by the DeNet dev team.

---

## 🚀 Quick Start

**Not sure which folder to use?**

| Your Setup | Use |
|---|---|
| 1 wallet, any number of nodes | 📁 `Linux-Single-Wallet/` |
| 2–4 wallets, different passwords | 📁 `Linux-Multi-Wallet/` |
| Windows PC | 📁 `Windows/` |
| macOS | 📁 `macOS/` |

---

## 📁 Repository Structure

```
NodePulse/
│
├── 📁 Linux-Single-Wallet/     ← Beginner friendly — 1 wallet
│   ├── denet-monitor.sh        Monitor + auto-restart (cron every 5 min)
│   ├── denet-bot-listener.sh   Telegram bot (systemd service)
│   ├── denet-update.sh         RC release updater
│   ├── setup-monitor-linux.sh  One-click installer
│   └── start-nodes.sh          Simple node starter
│
├── 📁 Linux-Multi-Wallet/      ← Advanced — up to 4 wallets
│   ├── denet-monitor.sh        Multi-wallet monitor
│   ├── denet-bot-listener.sh   Bot — groups nodes by wallet
│   ├── denet-update.sh         RC release updater
│   ├── setup-monitor-linux.sh  One-click installer
│   └── start-nodes.sh          Node starter
│
├── 📁 Windows/                 ← 🔜 Coming Soon
│   ├── denet-monitor.ps1       PowerShell monitor template
│   └── README.md
│
├── 📁 macOS/                   ← 🔜 Coming Soon
│   ├── denet-monitor.sh        macOS monitor template
│   └── README.md
│
├── 📁 docs/
│   └── NodePulse_Community_Guide.docx
│
├── nodepulse.html              PWA Dashboard + Telegram Mini App
├── nodepulse-wizard.html       Setup Wizard — generates configured scripts
└── manifest.json               PWA manifest
```

---

## ✨ Features

### 🔍 Auto-Monitor (cron every 5 min)
- Auto-restarts crashed nodes
- **PID tracking** — saves every 5 min, accurate history after reboots
- **Downtime tracking** — when node went down, offline duration
- **Penalty tracking** — alerts at 5, 8, 10 missed proof cycles
- Disk usage monitoring — alerts at 85%
- Node log error scanning
- Hourly heartbeat with full status
- Daily summary at your local time

### 🤖 Telegram Bot Commands
| Command | Description |
|---|---|
| `/status` | Live status — PID, uptime, restarts, penalties |
| `/restart YOUR_LICENSE` | Restart a specific node |
| `/restartall` | Restart all nodes |
| `/chain` | On-chain TX links per wallet |
| `/penalties` | Penalty count per node (0–10) |
| `/restarts` | Restart count per node |
| `/history` | Last downtime per node — UTC + local time |
| `/disk` | Storage drive usage |
| `/version` | Current denode binary version |
| `/resetcounts` | Reset restart counters |
| `/help` | All commands |

### 📱 NodePulse Dashboard (PWA + Telegram Mini App)
- Blockchain status — ONLINE / PENDING / OFFLINE
- Last on-chain transaction timestamp
- Local process status + uptime + penalties
- Disk usage bars per node
- Restart buttons per node
- Auto-refreshes every 30 seconds
- Install on phone home screen as PWA
- Works as Telegram Mini App

### ⬆️ RC Updater
```bash
denet-update --check     # See available releases
denet-update rc13        # Install rc13
denet-update latest      # Install latest
```

---

## 🔔 Penalty System

| Penalties | Status | Action |
|---|---|---|
| 0 | 🟢 Clean | Node submitting proofs normally |
| 1–4 | 🟡 Watch | Minor missed cycles |
| 5–7 | 🟠 Warning | Alert sent to Telegram |
| 8–9 | 🔴 Critical | Urgent alert — act now! |
| 10 | 🚫 Removed | Auto-restart triggered |

A successful proof submission resets penalties to 0. One cycle ≈ 90 minutes.

---

## 📱 NodePulse Dashboard Setup

### Option A — Tailscale ⭐ Recommended
No router config needed. Works behind any ISP.
```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
# Install Tailscale on phone → open http://YOUR_TAILSCALE_IP/nodepulse/
```

### Option B — Port Forwarding + DuckDNS (Dynamic IP)
Router port forwarding → port 80 → VM.
Access via `http://yourname-denet.duckdns.org/nodepulse/`

### Option C — Static Public IP
Forward port 80 → VM. Access via `http://YOUR_IP/nodepulse/`

---

## 🌍 Timezone Configuration

One line change — works for everyone:
```bash
LOCAL_TIMEZONE="Europe/Berlin"       # Germany
LOCAL_TIMEZONE="America/New_York"    # US East
LOCAL_TIMEZONE="Asia/Manila"         # Philippines
LOCAL_TIMEZONE="Asia/Kolkata"        # India
LOCAL_TIMEZONE="Asia/Singapore"      # Singapore
LOCAL_TIMEZONE="America/Los_Angeles" # US West
LOCAL_TIMEZONE="UTC"                 # Universal
```

---

## 🖥️ Platform Support

| Platform | Status | Notes |
|---|---|---|
| 🐧 Linux (Ubuntu 20.04 / 22.04) | ✅ **Fully Supported** | Single + Multi-wallet |
| 🪟 Windows 10/11 | 🔜 **Coming Soon** | Template available |
| 🍎 macOS 12+ | 🔜 **Coming Soon** | Template available |

---

## ⚠️ Known Limitations

- **Process ≠ Online** — monitor checks if process is running, not if proofs are being submitted on-chain
- **Blockchain status** — NodePulse v2 queries on-chain data — requires wallet address in dashboard config
- Windows and macOS are templates — not fully tested yet

---

## 🗺️ Roadmap

### ✅ v1.0
Auto-restart, PID tracking, downtime history, Telegram bot, NodePulse PWA, RC updater

### ✅ v2.0 (Current)
- Penalty tracking and alerts
- Multi-wallet support (up to 4 wallets)
- Configurable timezone
- Accurate PID history after reboots
- /penalties, /chain Telegram commands
- Blockchain status in dashboard
- Setup Wizard

### 🔜 v3.0 (Planned)
- Pool number monitoring
- Smart restart — only if process AND blockchain confirm down
- Full Windows & macOS tested support
- Multi-VM support
- Mobile app

---

## 🤝 Contributing

Built for the DeNet Datakeeper community.
- Open an issue for bugs
- Submit a PR for improvements
- Share in the [DeNet Discord](https://discord.gg/denet)

---

## 📄 License

MIT — free to use, modify, and share.

---

*Built with ❤️ by a DeNet Datakeeper — 6 nodes, Ubuntu VM + QNAP NAS*
