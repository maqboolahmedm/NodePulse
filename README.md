# NodePulse 🟡

**Community monitoring, alerting, and intelligence for DeNet Datakeeper nodes.**

NodePulse is a free, open-source toolkit built by the DeNet community, for the DeNet community. It monitors your nodes 24/7, sends Telegram alerts, diagnoses issues automatically, and lets you control your nodes from anywhere — all without any cloud dependency.

---

## Features

- **Real-time monitoring** — checks all nodes every 5 minutes, alerts on failures
- **Telegram bot control** — restart nodes, check status, view chain/disk/penalties remotely
- **NodePulse Guard** — AI-style health scoring and diagnosis engine per node (0–100)
- **NodePulse IP Watch** — DuckDNS dynamic DNS auto-updater
- **RC updater** — one-command DeNet binary upgrade with auto-restart
- **PWA Dashboard** — mobile-friendly web dashboard via browser
- **Setup Wizard** — guided web UI to generate your full install command in seconds
- **RAM/cache cleaner** — lightweight cleanup script, no alerts, no Telegram
- **Cross-platform** — Linux (Single & Multi-Wallet), Windows, macOS

---

## Supported Platforms

| Platform | Folder | Status |
|---|---|---|
| Linux — Single Wallet | `Linux-Single-Wallet/` | ✅ Stable |
| Linux — Multi Wallet (up to 4) | `Linux-Multi-Wallet/` | ✅ Stable |
| Windows | `Windows/` | 🧪 Community testing |
| macOS | `macOS/` | 🧪 Community testing |

---

## Quick Start

### Linux (Recommended)

1. Clone the repo to your home directory:
```bash
git clone https://github.com/maqboolahmedm/NodePulse.git ~/NodePulse
```

2. Open the Setup Wizard in your browser:
```
http://<your-vm-ip>/nodepulse/wizard.html
```

3. Fill in your credentials, copy the generated command, paste it in your terminal.

4. Done. NodePulse is running.

> **No wizard?** See the manual setup guide in your platform's `README.md`.

---

## File Structure

```
NodePulse/
├── Linux-Single-Wallet/       ← Single wallet, any number of licenses
│   ├── nodepulse-monitor.sh
│   ├── nodepulse-bot-listener.sh
│   ├── nodepulse-guard.sh
│   ├── nodepulse-ip-watch.sh
│   ├── nodepulse-denet-update.sh
│   ├── nodepulse-setup.sh
│   ├── nodepulse-proxy.py
│   ├── nodepulse-proxy.service
│   ├── nodepulse-cleanup.sh
│   └── README.md
├── Linux-Multi-Wallet/        ← Up to 4 wallets, different passwords
│   └── (same files)
├── Windows/
│   ├── nodepulse-monitor.ps1
│   ├── nodepulse-clean-cache.ps1
│   └── README.md
├── macOS/
│   ├── nodepulse-monitor.sh
│   ├── nodepulse-clean-cache.sh
│   └── README.md
├── docs/
│   └── COMMUNITY_GUIDE.md
├── nodepulse.html             ← PWA dashboard
├── nodepulse-wizard.html      ← Setup wizard
├── nodepulse-manifest.json
└── README.md
```

---

## Architecture

```
nodepulse-monitor.sh    → cron (every 5 min)  → writes status.json
nodepulse-guard.sh      → cron (every 5 min)  → health scores + Telegram alerts
nodepulse-ip-watch.sh   → cron (every 15 min) → DuckDNS update
nodepulse-bot-listener  → systemd             → reads .bot_trigger → executes commands
nodepulse-proxy.py      → systemd (port 8765) → writes .bot_trigger
Browser / Dashboard     → http://<ip>:8765/cmd → proxy → trigger → bot
```

---

## Telegram Bot Commands

| Command | Description |
|---|---|
| `/status` or `/s` | Full node status |
| `/restartall` | Restart all nodes |
| `/restart LICENSE` | Restart a specific node |
| `/chain` | Latest chain block per node |
| `/penalties` | Penalty counts per node |
| `/restarts` | Restart counts per node |
| `/history` | Recent event history |
| `/disk` | Storage disk usage |
| `/version` | Current DeNet binary version |
| `/resetcounts` | Reset restart/event counters |
| `/help` | Command list |

---

## NodePulse Guard — Health Scoring

Guard runs every 5 minutes and assigns each node a health score from 0 to 100.

| Condition | Score Change |
|---|---|
| HEALTHY | +2 per cycle |
| PENDING (proof 95–190 min ago) | −3 |
| STALE (no proof 190+ min) | −10 |
| PROOF_FAIL (2+ times) | −8 |
| RPC_ERROR (2+ times) | −8 |
| RPC_TIMEOUT (3+ times) | −8 |
| TX_NOT_MINED (3+ times) | −8 |
| LOW_GAS (3+ times) | −3 |
| NO_FUNDS | −20 (URGENT alert) |

- 30-minute cooldown between alerts (no spam)
- Hourly health report via Telegram

---

## DeNet Node Cycle Reference

```
FillRoothash   → ~15 min
HoldData       → ~60 min  (no log activity — this is normal)
CollectProofs  → ~15 min
Total cycle    → ~90 min

1 penalty per missed cycle
10 penalties  → pool removal (~15 hours to recover)
Restart is FREE while still in pool
Successful proof resets penalties to 0
```

---

## DeNet RC14 Notes

RC14-dev1 introduces a new interactive CLI config format:
- Config saved per-node: `~/.denode/<wallet>/config-<license>.json`
- Storage path: `/mnt/Denet-Storage/<license>/denode.storage-<license>`
- Pool Occupancy metric now visible in logs (e.g. `31/31 = 100%`)

Use `nodepulse-denet-update.sh` to upgrade. Updated for RC14 config format.

---

## Requirements

- Ubuntu 20.04+ (or any modern Debian-based Linux)
- `bash`, `curl`, `jq`, `python3`
- A Telegram bot (create one via [@BotFather](https://t.me/BotFather))
- DeNet Datakeeper binary installed at `/usr/bin/denode`
- `nginx` (for dashboard, optional)

---

## Contributing

NodePulse is community-built. If you find a bug, have a feature idea, or want to improve documentation — pull requests are welcome.

---

## License

MIT — free to use, fork, and improve.

---

*Built by the DeNet community. Not an official DeNet product.*
