# NodePulse — Linux Multi Wallet

Monitor and control DeNet Datakeeper nodes across **up to 4 wallets** with different passwords on Linux.

Use this setup if your licenses are spread across multiple wallet addresses (each with its own password).
For a single wallet, use `Linux-Single-Wallet/` instead — it is simpler to configure.

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
2. Select **Multi Wallet** tab
3. Add each wallet with its licenses, password, and storage path
4. Fill in shared credentials (bot token, chat ID, timezone)
5. Click **Generate Command**
6. Copy and paste the output in your terminal

### Option B — Manual Setup

1. Clone and prepare files:
   ```bash
   git clone https://github.com/maqboolahmedm/NodePulse.git ~/NodePulse
   cp ~/NodePulse/Linux-Multi-Wallet/* ~/NodePulse/
   chmod +x ~/NodePulse/*.sh ~/NodePulse/*.py
   ```

2. Edit the wallet config block at the top of each script. Example:
   ```bash
   # Wallet 1
   WALLET_1="0xAAAA..."
   PASSWORD_1="password1"
   LICENSES_1="1072 1864"

   # Wallet 2
   WALLET_2="0xBBBB..."
   PASSWORD_2="password2"
   LICENSES_2="1865 1866"
   ```

3. Run the setup script:
   ```bash
   bash ~/NodePulse/nodepulse-setup.sh
   ```

---

## Configuration Variables

### Shared (all wallets)

| Variable | Description | Example |
|---|---|---|
| `BOT_TOKEN` | Telegram bot token | `123456:ABCdef...` |
| `CHAT_ID` | Your Telegram chat ID | `123456789` |
| `TIMEZONE` | Your timezone | `Asia/Kolkata` |
| `STORAGE_PATH` | Base storage path | `/mnt/Denet-Storage` |

### Per Wallet (repeat for each wallet, up to 4)

| Variable | Description | Example |
|---|---|---|
| `WALLET_N` | Wallet address | `0x0caC3...` |
| `PASSWORD_N` | Wallet password | `yourpassword` |
| `LICENSES_N` | Space-separated license IDs | `1072 1864` |

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
nodepulse-monitor.sh   → iterates all wallets/licenses → alerts on failure
nodepulse-guard.sh     → scores each node 0-100 → hourly Telegram report
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

Status cards show all nodes across all wallets in a single view.

---

## Updating the DeNet Binary (RC Upgrade)

```bash
bash ~/NodePulse/nodepulse-denet-update.sh
```

This script:
1. Downloads the specified RC version
2. Stops all running nodes across all wallets
3. Installs the new binary
4. Restarts all nodes with their per-wallet configs
5. Verifies all nodes are running

> **RC14+ note:** Config files are stored per-node at  
> `~/.denode/<wallet>/config-<license>.json`  
> The updater handles multi-wallet configs automatically.

---

## Troubleshooting

**One wallet's nodes not alerting:**
- Verify that wallet's variables are set correctly in the scripts
- Test manually: `bash ~/NodePulse/nodepulse-monitor.sh`

**Bot not responding to commands:**
- Check service: `sudo systemctl status nodepulse-bot`
- Check proxy: `curl "http://localhost:8765/cmd?text=/status"`

**`/restart LICENSE` restarts wrong wallet's node:**
- The bot looks up the license across all wallets automatically
- If license IDs overlap between wallets, ensure each is unique

**Guard health scores missing for some nodes:**
- Check guard log: `tail -50 ~/.nodepulse/guard.log`
- Verify all license IDs are listed in the LICENSES_N variables

---

## Files Created at Runtime

```
~/.nodepulse/             ← logs directory
~/.nodepulse_guard/       ← guard state (health scores, cooldowns)
~/.denode/.bot_trigger    ← command trigger file (proxy → listener)
/var/www/html/nodepulse/status.json   ← dashboard data (all wallets)
```
