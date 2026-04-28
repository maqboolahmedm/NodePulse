# ⬡ NodePulse — DeNet Node Monitor

> **Community-built monitoring system for DeNet Datakeeper Nodes**
> Built by a Datakeeper running 6 nodes on Ubuntu VM + QNAP NAS.
> Shared with the DeNet community — free, open-source, MIT licensed.

---

## 🚀 Quick Start

| Your Setup | Use This Folder |
|---|---|
| 1 wallet, any number of nodes | 📁 `Linux-Single-Wallet/` |
| 2–4 wallets, different passwords | 📁 `Linux-Multi-Wallet/` |
| Windows PC | 📁 `Windows/` (template) |
| macOS | 📁 `macOS/` (template) |

---

## 📁 Repository Structure

```
NodePulse/
├── Linux-Single-Wallet/
│   ├── nodepulse-monitor.sh        Monitor + auto-restart (cron every 5 min)
│   ├── nodepulse-bot-listener.sh   Telegram bot (systemd service)
│   ├── nodepulse-guard.sh          Intelligence agent + health scoring (cron every 5 min)
│   ├── nodepulse-ip-watch.sh       Public IP monitor + DuckDNS (cron every 15 min)
│   ├── nodepulse-update.sh         RC version updater
│   ├── nodepulse-setup.sh          One-click installer
│   ├── nodepulse-proxy.py          Web app command bridge (systemd service)
│   ├── nodepulse-proxy.service     Proxy systemd service file
│   └── README.md
│
├── Linux-Multi-Wallet/
│   ├── nodepulse-monitor.sh        Multi-wallet monitor (up to 4 wallets)
│   ├── nodepulse-bot-listener.sh   Bot — nodes grouped by wallet
│   ├── nodepulse-guard.sh          Intelligence agent
│   ├── nodepulse-ip-watch.sh       IP monitor + DuckDNS
│   ├── nodepulse-update.sh         RC version updater
│   ├── nodepulse-setup.sh          One-click installer
│   ├── nodepulse-proxy.py          Web app command bridge
│   ├── nodepulse-proxy.service     Proxy systemd service file
│   └── README.md
│
├── Windows/
│   ├── nodepulse-monitor.ps1       PowerShell template (pilot)
│   └── README.md
│
├── macOS/
│   ├── nodepulse-monitor.sh        macOS template (pilot)
│   └── README.md
│
├── docs/
│   └── NodePulse_Community_Guide_v3.docx
│
├── nodepulse.html                  PWA Dashboard + Telegram Mini App
├── nodepulse-manifest.json         PWA manifest
└── README.md
```

---

## ✨ Features

### 🔍 NodePulse Monitor
- Auto-restarts crashed nodes with full downtime tracking
- PID tracking — accurate history after reboots
- Penalty tracking — alerts at 5, 8, 10 penalties
- Auto-restart at 10 penalties before pool removal
- Disk usage monitoring — alerts at 85%
- Hourly heartbeat + daily summary
- On-chain status from node logs — no external API needed

### 🤖 Telegram Bot Commands
| Command | Description |
|---|---|
| `/status` | Live status — PID, uptime, restarts, penalties |
| `/restart 1072` | Restart specific node |
| `/restartall` | Restart all nodes (free while in pool) |
| `/chain` | On-chain status per node from logs |
| `/penalties` | Penalty count per node |
| `/restarts` | Restart counts |
| `/history` | Last downtime event |
| `/disk` | Storage usage |
| `/version` | denode binary version |
| `/resetcounts` | Reset restart counters |
| `/help` | All commands |

### 🛡️ NodePulse Guard
- Diagnoses node issues with confidence scoring
- Per-node health scores (0–100)
- Cooldown system — no repeat alerts within 30 min
- Detects: PROOF_FAIL, RPC_ERROR, RPC_TIMEOUT, NO_FUNDS, LOW_GAS and more
- Hourly health report via Telegram

### 🌐 NodePulse IP Watch
- Monitors public IP changes every 15 min
- Auto-updates DuckDNS on IP change
- Telegram alert on IP change

### 📱 NodePulse Dashboard (PWA)
- Live dashboard via nginx on your VM
- Per-node: process status, chain status, uptime, penalties, pool, stage, last proof
- All bot commands accessible via buttons
- Install on phone home screen as PWA
- Works as Telegram Mini App

### ⬆️ RC Updater
```bash
nodepulse-update --check     # List available releases
nodepulse-update rc14        # Install rc14
nodepulse-update latest      # Install latest
```
Automatically: stops nodes → deletes .denode → installs → restarts

---

## 🔔 Penalty System

| Penalties | Status | Action |
|---|---|---|
| 0 | 🟢 Clean | Normal |
| 1–4 | 🟡 Watch | Monitor |
| 5–7 | 🟠 Warning | Alert sent |
| 8–9 | 🔴 Critical | Urgent alert |
| 10 | 🚫 Removed | Auto-restart |

One cycle ≈ 90 min · Restart is FREE while in pool · Successful proof resets penalties to 0

---

## 📱 Dashboard Access

| Method | URL | Notes |
|---|---|---|
| Tailscale ⭐ | `http://YOUR_TAILSCALE_IP/nodepulse/` | Recommended — no router config |
| DuckDNS | `http://yourname.duckdns.org/nodepulse/` | Dynamic IP support |
| Static IP | `http://YOUR_IP/nodepulse/` | Fixed public IP |

---

## 🖥️ Platform Support

| Platform | Status |
|---|---|
| 🐧 Linux (Ubuntu 20.04/22.04) | ✅ Fully Supported |
| 🪟 Windows 10/11 | 🔜 Coming Soon (template available) |
| 🍎 macOS 12+ | 🔜 Coming Soon (template available) |

---

## 🗺️ Roadmap

### ✅ v2.0 (Current)
Auto-restart · Penalty tracking · Multi-wallet · Timezone config · On-chain status from logs · NodePulse Guard · IP Watch · PWA Dashboard · Command Proxy · RC Updater

### 🔜 v3.0 (Planned)
Full Windows & macOS support · Mobile app · Pool number monitoring · Smart restart logic

---

## 🤝 Contributing
Open an issue for bugs · Submit a PR for improvements · Share in DeNet Discord

---

## 📄 License
MIT — free to use, modify, and share.

---

*Built with ❤️ by a DeNet Datakeeper — 6 nodes, Ubuntu VM + QNAP NAS*
