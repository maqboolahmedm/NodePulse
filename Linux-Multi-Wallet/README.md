# 🐧 NodePulse — Linux Multi-Wallet Setup Guide

> For advanced Datakeepers running nodes across multiple wallet addresses
> Supports up to 4 wallets with different passwords — unlimited nodes

---

## When to use this folder

| Situation | Use |
|---|---|
| 1 wallet, up to 10 nodes | `linux-single-wallet/` |
| 2–4 wallets, any number of nodes | `linux-multi-wallet/` ← you are here |

---

## Files in this folder

| File | Purpose | How it runs |
|---|---|---|
| `denet-monitor-lmw.sh` | Multi-wallet monitor | cron every 5 min |
| `denet-bot-listener-lmw.sh` | Telegram bot — groups nodes by wallet | systemd service |

---

## Configuration

Open `denet-monitor-lmw.sh` and fill in your wallet details:

```bash
# Wallet 1
WALLET_1_ADDRESS="0x..."
WALLET_1_PASSWORD="your_password_1"
WALLET_1_LICENSES=(1072 1864 1865)

# Wallet 2
WALLET_2_ADDRESS="0x..."
WALLET_2_PASSWORD="your_password_2"
WALLET_2_LICENSES=(2001 2002 2003)

# Wallet 3 (leave empty if not used)
WALLET_3_ADDRESS=""
WALLET_3_PASSWORD=""
WALLET_3_LICENSES=()

# Wallet 4 (leave empty if not used)
WALLET_4_ADDRESS=""
WALLET_4_PASSWORD=""
WALLET_4_LICENSES=()
```

Then fill in per-node config:

```bash
# For each license, set wallet, port, storage, RPC
NODE_WALLET[1072]="$WALLET_1_ADDRESS"
NODE_PORT[1072]=55050
NODE_STORAGE[1072]="/mnt/storage/1072"
NODE_RPC[1072]="https://peaq.api.onfinality.io/rpc?apikey=YOUR_KEY"
```

Do the same in `denet-bot-listener-lmw.sh`.

---

## Install

```bash
mkdir -p ~/DeNet/multi-wallet
cp denet-monitor-lmw.sh denet-bot-listener-lmw.sh ~/DeNet/multi-wallet/
chmod +x ~/DeNet/multi-wallet/*.sh

# Add cron job
(crontab -l 2>/dev/null; echo "*/5 * * * * /home/YOUR_USERNAME/DeNet/multi-wallet/denet-monitor-lmw.sh") | crontab -

# Create systemd service
sudo tee /etc/systemd/system/denet-bot-multi.service << 'EOF'
[Unit]
Description=DeNet Telegram Bot Multi-Wallet
After=network-online.target

[Service]
Type=simple
User=YOUR_USERNAME
ExecStart=/home/YOUR_USERNAME/DeNet/multi-wallet/denet-bot-listener-lmw.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable denet-bot-multi
sudo systemctl start denet-bot-multi
```

---

## Telegram Commands

All commands work across all wallets. Nodes are grouped by wallet in responses:

```
📊 DeNet Node Status
💼 Wallet 1:
🟢 1072 — PID 3401 — Up: 5h — R:0 — 🟢P:0/10
🟢 1864 — PID 3486 — Up: 5h — R:0 — 🟢P:0/10

💼 Wallet 2:
🟢 2001 — PID 3565 — Up: 5h — R:0 — 🟢P:0/10
🟢 2002 — PID 3646 — Up: 5h — R:0 — 🟢P:0/10
```

| Command | Description |
|---|---|
| `/status` | All nodes grouped by wallet |
| `/restart 1072` | Restart specific node (any wallet) |
| `/restartall` | Restart all nodes across all wallets |
| `/chain` | Subscan links per wallet |
| `/penalties` | Penalties grouped by wallet |
| `/history` | Downtime history per node |
| `/disk` | Storage usage per node |
| `/restarts` | Restart counts |
| `/version` | denode binary version |
| `/help` | All commands |

---

## Timezones

```bash
LOCAL_TIMEZONE="Asia/Kolkata"        # India
LOCAL_TIMEZONE="Europe/Berlin"       # Germany
LOCAL_TIMEZONE="America/New_York"    # US East
LOCAL_TIMEZONE="Asia/Manila"         # Philippines
LOCAL_TIMEZONE="Asia/Singapore"      # Singapore
LOCAL_TIMEZONE="UTC"                 # Universal
```
