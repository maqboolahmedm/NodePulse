# 🐧 NodePulse — Linux Single Wallet

> For Datakeepers running **1 wallet** with any number of nodes.

## Files

| File | Purpose | How it runs |
|---|---|---|
| `nodepulse-monitor.sh` | Auto-restart, penalties, heartbeat | cron every 5 min |
| `nodepulse-bot-listener.sh` | Telegram bot commands | systemd service |
| `nodepulse-guard.sh` | Intelligence agent, health scoring | cron every 5 min |
| `nodepulse-ip-watch.sh` | Public IP monitor + DuckDNS update | cron every 15 min |
| `nodepulse-update.sh` | RC version updater | Run manually |
| `nodepulse-setup.sh` | One-click installer | Run once |
| `nodepulse-proxy.py` | Web app command bridge | systemd service |
| `nodepulse-proxy.service` | Systemd service for proxy | Install once |

## Quick Start

```bash
# 1. Clone repo
git clone https://github.com/maqboolahmedm/NodePulse.git
cd NodePulse/Linux-Single-Wallet

# 2. Set your Telegram credentials in all files at once
find . -name "nodepulse-*" -exec sed -i \
  's|YOUR_TELEGRAM_BOT_TOKEN|YOUR_ACTUAL_TOKEN|g;
   s|YOUR_TELEGRAM_CHAT_ID|YOUR_ACTUAL_CHAT_ID|g' {} +

# 3. Fill in remaining YOUR_XXX values in nodepulse-monitor.sh
nano nodepulse-monitor.sh

# 4. Install everything
bash nodepulse-setup.sh
```

## Timezones
`Asia/Kolkata` · `Europe/Berlin` · `America/New_York` · `Asia/Manila` · `Asia/Singapore` · `UTC`
