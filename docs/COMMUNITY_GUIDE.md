# NodePulse Community Guide

**Everything you need to set up, run, and get the most out of NodePulse.**

This guide is written for DeNet Datakeepers who are new to NodePulse or want a deeper understanding of how everything works.

---

## Table of Contents

1. [What is NodePulse?](#what-is-nodepulse)
2. [Before You Start](#before-you-start)
3. [Choosing Your Setup Type](#choosing-your-setup-type)
4. [Installation — Step by Step](#installation)
5. [Understanding Your Nodes](#understanding-your-nodes)
6. [Telegram Bot Commands](#telegram-bot-commands)
7. [NodePulse Guard — Health Scoring](#nodepulse-guard)
8. [NodePulse IP Watch — Dynamic DNS](#nodepulse-ip-watch)
9. [Upgrading DeNet RC Versions](#upgrading-denet-rc-versions)
10. [Dashboard & Setup Wizard](#dashboard--setup-wizard)
11. [Common Issues & Fixes](#common-issues--fixes)
12. [DeNet Node Cycle Reference](#denet-node-cycle-reference)
13. [RC14 Migration Notes](#rc14-migration-notes)
14. [FAQ](#faq)

---

## What is NodePulse?

NodePulse is a free, open-source monitoring and control toolkit for DeNet Datakeeper node operators.

It gives you:
- **Alerts when something goes wrong** — Telegram notifications within 5 minutes of a node failure
- **Health intelligence** — a per-node scoring system that tells you how healthy each node is, not just whether it's running
- **Remote control** — restart nodes, check status, view chain height and penalties, all from Telegram
- **A web dashboard** — a mobile-friendly PWA that shows all your nodes at a glance
- **Automated IP updates** — keeps your DuckDNS domain pointing at your server even if your ISP changes your IP
- **One-click RC upgrades** — download, install, and restart with a single command

NodePulse runs entirely on your own machine. No accounts, no cloud, no subscription.

---

## Before You Start

You will need:

| Requirement | Notes |
|---|---|
| A Linux server or VM | Ubuntu 20.04+ recommended |
| DeNet Datakeeper installed | Binary at `/usr/bin/denode` |
| At least one active license | With wallet address and password |
| A Telegram account | Free |
| A Telegram bot | Free — create via [@BotFather](https://t.me/BotFather) |
| Your Telegram Chat ID | Free — get via [@userinfobot](https://t.me/userinfobot) |
| (Optional) DuckDNS account | Free — only needed for IP Watch feature |

**Getting your bot token:**
1. Open Telegram, search for `@BotFather`
2. Send `/newbot`
3. Follow the prompts — choose a name and username for your bot
4. BotFather will give you a token like `123456789:ABCdefGhIjKlmNoPQrsTUvwXyz`
5. Send your bot a message first (so it can message you back)

**Getting your Chat ID:**
1. Open Telegram, search for `@userinfobot`
2. Send `/start`
3. It will reply with your ID — a number like `987654321`

---

## Choosing Your Setup Type

**Single Wallet** — all your licenses use one wallet address and password.
→ Use `Linux-Single-Wallet/`

**Multi Wallet** — your licenses are spread across 2–4 wallet addresses with different passwords.
→ Use `Linux-Multi-Wallet/`

If you only have one wallet (even with 6 licenses), use Single Wallet. It's simpler to configure and maintain.

---

## Installation

### The Easy Way — Setup Wizard

If your VM is running nginx, the fastest way is the setup wizard:

```
http://<your-vm-ip>/nodepulse/wizard.html
```

The wizard walks you through every field and generates a complete install command. You copy it, paste it in your terminal, and NodePulse installs itself.

### Manual Installation

**Step 1 — Clone the repo**
```bash
git clone https://github.com/maqboolahmedm/NodePulse.git ~/NodePulse
```

**Step 2 — Copy files for your setup type**
```bash
# For single wallet:
cp ~/NodePulse/Linux-Single-Wallet/* ~/NodePulse/

# For multi-wallet:
cp ~/NodePulse/Linux-Multi-Wallet/* ~/NodePulse/
```

**Step 3 — Make scripts executable**
```bash
chmod +x ~/NodePulse/*.sh ~/NodePulse/*.py
```

**Step 4 — Edit your configuration**
```bash
nano ~/NodePulse/nodepulse-monitor.sh
```

Set at minimum:
- `BOT_TOKEN`
- `CHAT_ID`
- `WALLET` (and `PASSWORD`)
- `LICENSES` (space-separated)
- `STORAGE_PATH`
- `TIMEZONE`

**Step 5 — Run setup**
```bash
bash ~/NodePulse/nodepulse-setup.sh
```

This installs cron jobs, systemd services, and verifies everything is running.

**Step 6 — Verify**
```bash
# Check services
sudo systemctl status nodepulse-bot
sudo systemctl status nodepulse-proxy

# Check cron
crontab -l | grep nodepulse

# Test monitor
bash ~/NodePulse/nodepulse-monitor.sh
```

You should receive a Telegram message with your node status within a few seconds of the last command.

---

## Understanding Your Nodes

NodePulse checks these things for each node every 5 minutes:

| Check | What it means |
|---|---|
| **Process running** | Is the denode process alive? |
| **Last proof time** | When did the node last submit a proof? |
| **Proof age** | How many minutes since the last proof? |
| **Penalties** | How many penalties has this node accumulated? |
| **Chain height** | Is the node synced with the network? |
| **Disk space** | Is storage getting full? |
| **Wallet balance** | Does the wallet have enough gas? |

**Alert thresholds (defaults):**
- No proof for 95+ minutes → `PENDING` warning
- No proof for 190+ minutes → `STALE` critical alert
- 5+ penalties → warning alert
- Disk usage above 90% → disk warning
- Low gas balance → urgent alert

---

## Telegram Bot Commands

Send these commands to your bot in Telegram. Commands work from anywhere — no VPN needed.

| Command | What it does |
|---|---|
| `/status` or `/s` | Full status of all nodes — health, proof time, penalties |
| `/restartall` | Restart all nodes sequentially |
| `/restart 1072` | Restart a specific node by license ID |
| `/chain` | Latest chain block number per node |
| `/penalties` | Penalty count per node |
| `/restarts` | How many times each node has been restarted |
| `/history` | Recent events — restarts, alerts, failures |
| `/disk` | Storage usage per license |
| `/version` | Current DeNet binary version running |
| `/resetcounts` | Reset restart and event counters |
| `/help` | Show all available commands |

**Pro tip:** `/s` is a shortcut for `/status` — fastest way to check in from your phone.

---

## NodePulse Guard

Guard is NodePulse's health intelligence engine. It goes beyond "is the node running?" and gives each node a **health score from 0 to 100**.

### How Scoring Works

Guard runs every 5 minutes and adjusts each node's score based on observed conditions:

| Condition | Score Change |
|---|---|
| HEALTHY (proof on time) | +2 per cycle |
| PENDING (proof 95–190 min ago) | −3 |
| STALE (no proof 190+ min) | −10 |
| PROOF_FAIL (2+ recent failures) | −8 |
| RPC_ERROR (2+ recent errors) | −8 |
| RPC_TIMEOUT (3+ recent timeouts) | −8 |
| TX_NOT_MINED (3+ recent failures) | −8 |
| LOW_GAS (3+ recent occurrences) | −3 |
| NO_FUNDS | −20 (immediate URGENT alert) |

### Score Thresholds

| Score | Status |
|---|---|
| 80–100 | 🟢 Excellent |
| 60–79 | 🟡 Good |
| 40–59 | 🟠 Degraded |
| 20–39 | 🔴 Poor |
| 0–19 | 🚨 Critical |

### Alerts

- Individual node alerts fire when score drops below threshold
- **30-minute cooldown** between alerts — no spam
- Hourly health report sent to Telegram showing all node scores

### Guard State Files

Guard stores per-node state in `~/.nodepulse_guard/`:
```
~/.nodepulse_guard/
├── score_1072        ← current health score for license 1072
├── score_1864
├── last_alert_1072   ← timestamp of last alert (for cooldown)
└── ...
```

---

## NodePulse IP Watch

If your internet connection has a dynamic IP (most home/datacenter connections do), your DuckDNS domain will eventually stop pointing to your server.

NodePulse IP Watch solves this:
- Runs every 15 minutes via cron
- Checks your current public IP
- If it changed, updates your DuckDNS domain automatically
- Sends a Telegram notification when IP changes

### Setup

You need a free DuckDNS account:
1. Go to [duckdns.org](https://www.duckdns.org)
2. Log in with Google or GitHub
3. Create a subdomain (e.g. `mynodes.duckdns.org`)
4. Copy your token from the DuckDNS dashboard

Add these to `nodepulse-ip-watch.sh`:
```bash
DUCKDNS_TOKEN="your-token-here"
DUCKDNS_DOMAIN="mynodes"    # just the subdomain, not the full URL
```

---

## Upgrading DeNet RC Versions

When a new DeNet RC is released:

```bash
bash ~/NodePulse/nodepulse-denet-update.sh
```

The updater will:
1. Ask which RC version to install (or auto-detect the latest)
2. Stop all running nodes gracefully
3. Download and install the new binary
4. Restart all nodes with their existing configs
5. Verify all nodes came back online
6. Send a Telegram confirmation

> **Do not manually kill and restart nodes during an RC upgrade.**
> Let the updater handle the sequence to avoid penalty accumulation.

---

## Dashboard & Setup Wizard

### PWA Dashboard

The NodePulse dashboard is a Progressive Web App (PWA) — you can add it to your phone's home screen like a native app.

Access it at:
```
http://<your-vm-ip>/nodepulse/
```

It shows:
- All node status cards (health, proof time, penalties)
- Quick-action buttons (restart, check status)
- Live refresh every 30 seconds

### Setup Wizard

The wizard generates your full install command from a browser form — no manual script editing required.

Access it at:
```
http://<your-vm-ip>/nodepulse/wizard.html
```

Tabs:
- **Setup** — generate install command for Single or Multi Wallet
- **Services** — start/stop/restart systemd services
- **Cron** — view and manage cron entries

---

## Common Issues & Fixes

### "My node is STALE but it looks fine in the DeNet UI"

The DeNet node log uses `HoldData` phase which has no activity for ~60 minutes. This is **normal behavior**. NodePulse may flag this as PENDING but it is not an error.
**Fix:** Wait for the next cycle to complete. If the proof comes through, the score recovers automatically.

### "Bot not responding to commands"

```bash
# 1. Check bot service
sudo systemctl status nodepulse-bot

# 2. Check proxy
curl "http://localhost:8765/cmd?text=/status"

# 3. Check trigger file mechanism
echo "/status" > ~/.denode/.bot_trigger
sleep 10
cat ~/.nodepulse/monitor.log | tail -20
```

### "No Telegram messages at all"

```bash
# Test your bot token directly
curl "https://api.telegram.org/bot<YOUR_TOKEN>/sendMessage?chat_id=<YOUR_CHAT_ID>&text=test"
```

If this works, the token and chat ID are correct. If not, regenerate your token via @BotFather.

### "Guard sending too many alerts"

The 30-minute cooldown should prevent spam. If you're still getting flooded:
- Check if a node is genuinely in a failure loop
- Clear the guard state to reset: `rm ~/.nodepulse_guard/last_alert_*`

### "nodepulse-denet-update.sh fails mid-upgrade"

```bash
# Check which nodes are running
ps aux | grep denode

# Manually restart any stopped nodes
~/.denode/<wallet>/config-<license>.json  # for RC14+
denode start --config <config-file>
```

---

## DeNet Node Cycle Reference

Understanding the normal node cycle prevents false alarms:

```
Phase 1 — FillRoothash    ~15 minutes   (active log output)
Phase 2 — HoldData        ~60 minutes   (SILENT — no log output, this is normal)
Phase 3 — CollectProofs   ~15 minutes   (active log output)
─────────────────────────────────────────
Total cycle               ~90 minutes
```

**Penalty rules:**
- 1 penalty accumulated per missed proof cycle
- 10 penalties → removed from pool (~15 hours to re-enter)
- Restarting while still in pool = FREE (no penalty)
- Successful proof resets penalties to 0
- A node can accumulate penalties silently — always check `/penalties`

**Best restart practice:**
- Always restart a node BEFORE it hits 10 penalties
- Restarting at 8–9 penalties is safer than waiting
- After restart, the node re-enters its cycle from Phase 1

---

## RC14 Migration Notes

RC14-dev1 introduced significant changes to how node configuration is stored.

**What changed:**
- Config is now interactive CLI-based (no more config flags in the start command)
- Per-node config files: `~/.denode/<wallet>/config-<license>.json`
- Storage path pattern: `/mnt/Denet-Storage/<license>/denode.storage-<license>`
- New metric visible in logs: Pool Occupancy (e.g. `31/31 = 100%`)

**What NodePulse does:**
- `nodepulse-denet-update.sh` is updated to handle RC14 config format
- Monitor and Guard scripts detect per-node config paths automatically
- No manual migration needed if you use the updater script

**If you're migrating from RC13:**
```bash
# Run the updater — it handles the config conversion
bash ~/NodePulse/nodepulse-denet-update.sh
```

---

## FAQ

**Q: Does NodePulse require any paid services?**  
A: No. Everything is free — Telegram bots are free, DuckDNS is free, the software is open-source.

**Q: Will NodePulse interfere with my nodes?**  
A: No. NodePulse only reads node status and sends restart commands through the normal DeNet CLI. It does not modify node data or storage.

**Q: Can I run NodePulse on a different machine than my nodes?**  
A: The monitor can run remotely if it has SSH or API access to check node status. However, restart commands require local access. For most Datakeepers, NodePulse runs on the same VM as the nodes.

**Q: What if my Telegram bot token is compromised?**  
A: Revoke the token immediately via @BotFather (`/revoke`), generate a new one, and update `BOT_TOKEN` in all your scripts, then restart the bot service.

**Q: Does NodePulse store any of my data externally?**  
A: No. NodePulse only communicates with the Telegram API (to send you messages) and optionally DuckDNS (to update your IP). No data is sent anywhere else.

**Q: Can I use NodePulse with more than 6 nodes?**  
A: Yes. Add as many license IDs as you have to the `LICENSES` variable. There is no hard limit.

**Q: What is the difference between the Monitor and Guard?**  
A: The Monitor is your alarm system — it fires immediately when something is wrong. Guard is your health intelligence — it tracks trends over time and gives you a score, so you can see a node degrading before it fails.

---

*NodePulse is a community project. Not an official DeNet product.*  
*GitHub: github.com/maqboolahmedm/NodePulse*
