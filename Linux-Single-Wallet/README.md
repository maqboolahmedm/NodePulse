# NodePulse — Linux Single Wallet

Monitor and control your DeNet Datakeeper nodes from one wallet on Linux.

Use this setup if all your licenses share **one wallet address**.
For multiple wallets with different passwords, use `Linux-Multi-Wallet/` instead.

---

## What's Included

| File | Purpose | How It Runs |
|---|---|---|
| `nodepulse-monitor.sh` | Node health monitor + Telegram alerts | cron every 5 min |
| `nodepulse-guard.sh` | Health scoring + diagnosis engine | cron every 5 min |
| `nodepulse-ip-watch.sh` | DuckDNS dynamic IP updater | cron every 15 min |
| `nodepulse-bot-listener.sh` | Executes Telegram bot commands | systemd service |
| `nodepulse-proxy.py` | Local HTTP proxy for dashboard commands | systemd service |
| `nodepulse-proxy.service` | systemd unit for proxy | installed by setup |
| `nodepulse-denet-update.sh` | DeNet RC binary updater | run manually |
| `nodepulse-setup.sh` | One-click installer | run once |
| `nodepulse-cleanup.sh` | RAM/cache cleaner (no alerts) | run manually / cron |

---

## Requirements

- Ubuntu 20.04+ or any Debian-based Linux
- `bash`, `curl`, `jq`, `python3`
- DeNet Datakeeper binary at `/usr/bin/denode`
- Telegram bot token (get one from [@BotFather](https://t.me/BotFather))
- Your Telegram Chat ID

---

## Installation

### Option A — Setup Wizard (Recommended)

1. Open the wizard in your browser:
   ```
   http://<your-vm-ip>/nodepulse/wizard.html
   ```
2. Select **Single Wallet** tab
3. Fill in all fields (bot token, chat ID, wallet, password, licenses, timezone, storage path)
4. Click **Generate Command**
5. Copy the output and paste it in your terminal

### Option B — Manual Setup

1. Clone and prepare files:
   ```bash
   git clone https://github.com/maqboolahmedm/NodePulse.git ~/NodePulse
   cp ~/NodePulse/Linux-Single-Wallet/* ~/NodePulse/
   chmod +x ~/NodePulse/*.sh ~/NodePulse/*.py
   ```

2. Edit the config variables at the top of each script:
   ```bash
   nano ~/NodePulse/nodepulse-monitor.sh
   ```
   Set: `BOT_TOKEN`, `CHAT_ID`, `WALLET`, `PASSWORD`, `TIMEZONE`, `STORAGE_PATH`, license list

3. Run the setup script:
   ```bash
   bash ~/NodePulse/nodepulse-setup.sh
   ```

---

## Configuration Variables

| Variable | Description | Example |
|---|---|---|
| `BOT_TOKEN` | Telegram bot token | `123456:ABCdef...` |
| `CHAT_ID` | Your Telegram chat ID | `123456789` |
| `WALLET` | Your DeNet wallet address | `0x0caC3...` |
| `PASSWORD` | Wallet password | `yourpassword` |
| `TIMEZONE` | Your timezone | `Asia/Kolkata` |
| `STORAGE_PATH` | Base storage path | `/mnt/Denet-Storage` |
| `LICENSES` | Space-separated license IDs | `1072 1864 1865` |

---

## Cron Jobs (Auto-installed)

```cron
*/5  * * * * bash ~/NodePulse/nodepulse-monitor.sh >> ~/.nodepulse/monitor.log 2>&1
*/5  * * * * bash ~/NodePulse/nodepulse-guard.sh   >> ~/.nodepulse/guard.log   2>&1
*/15 * * * * bash ~/NodePulse/nodepulse-ip-watch.sh >> ~/.nodepulse/ipwatch.log 2>&1
```

---

## Services (Auto-installed)

```bash
# Check status
sudo systemctl status nodepulse-bot
sudo systemctl status nodepulse-proxy

# Restart
sudo systemctl restart nodepulse-bot
sudo systemctl restart nodepulse-proxy

# View logs
journalctl -u nodepulse-bot -f
journalctl -u nodepulse-proxy -f
```

---

## Architecture

```
nodepulse-monitor.sh   → checks nodes → sends Telegram alert on failure
nodepulse-guard.sh     → scores node health 0-100 → hourly report
nodepulse-ip-watch.sh  → checks public IP → updates DuckDNS if changed
nodepulse-bot-listener → polls ~/.denode/.bot_trigger → executes commands
nodepulse-proxy.py     → listens :8765 → writes .bot_trigger
Dashboard button       → POST :8765/cmd → proxy → trigger → bot executes
```

> **Note:** The bot listener does not respond to its own Telegram messages.
> Commands from the dashboard go through the proxy → trigger file → listener.
> This is by design and works reliably.

---

## Dashboard

If nginx is installed, the dashboard is available at:
```
http://<your-vm-ip>/nodepulse/
```

The dashboard reads `status.json` updated by `nodepulse-monitor.sh` every 5 minutes.

---

## Updating the DeNet Binary (RC Upgrade)

```bash
bash ~/NodePulse/nodepulse-denet-update.sh
```

This script:
1. Downloads the specified RC version
2. Stops all running nodes
3. Installs the new binary
4. Restarts all nodes with their configs
5. Verifies all nodes are running

> **RC14+ note:** Config files are stored per-node at  
> `~/.denode/<wallet>/config-<license>.json`  
> The updater handles this format automatically.

---

## Troubleshooting

**Nodes not alerting:**
- Check cron is running: `crontab -l | grep nodepulse`
- Check bot token and chat ID are correct
- Test manually: `bash ~/NodePulse/nodepulse-monitor.sh`

**Bot not responding to commands:**
- Check service: `sudo systemctl status nodepulse-bot`
- Check proxy: `curl "http://localhost:8765/cmd?text=/status"`
- Check trigger file: `cat ~/.denode/.bot_trigger`

**Guard not sending reports:**
- Check guard log: `tail -50 ~/.nodepulse/guard.log`
- Verify `~/.nodepulse_guard/` directory exists

**status.json not updating:**
- Check nginx is running: `sudo systemctl status nginx`
- Check file: `ls -la /var/www/html/nodepulse/status.json`

---

## Files Created at Runtime

```
~/.nodepulse/             ← logs directory
~/.nodepulse_guard/       ← guard state (health scores, cooldowns)
~/.denode/.bot_trigger    ← command trigger file (proxy → listener)
/var/www/html/nodepulse/status.json   ← dashboard data
```
