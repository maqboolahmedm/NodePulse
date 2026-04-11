<<<<<<< HEAD
#!/bin/bash

# ============================================================
# DeNet Monitor Setup Script — Linux (Ubuntu)
# User: maqbool | Ubuntu VM
# Sets up: cron job, systemd bot service, directories, aliases
# ============================================================

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "${GREEN}✅ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
info() { echo -e "${CYAN}ℹ️  $1${NC}"; }
err()  { echo -e "${RED}❌ $1${NC}"; exit 1; }

DENET_DIR="$HOME/DeNet"
DENODE_DIR="$HOME/.denode"
LOG_DIR="$DENODE_DIR/logs"

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  DeNet Monitor Setup — Linux (Ubuntu)${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 1. Create directories
info "Creating directories..."
mkdir -p "$DENET_DIR" "$LOG_DIR"
ok "Directories ready: $DENET_DIR | $LOG_DIR"

# 2. Check scripts are present
REQUIRED=("denet-monitor.sh" "denet-bot-listener.sh" "denet-update.sh")
for SCRIPT in "${REQUIRED[@]}"; do
  if [ ! -f "$DENET_DIR/$SCRIPT" ]; then
    warn "$SCRIPT not found in $DENET_DIR"
    info "Copy all scripts to $DENET_DIR first, then re-run setup."
    err "Missing scripts. Aborting."
  fi
done
ok "All scripts found in $DENET_DIR"

# 3. Set executable permissions
chmod +x "$DENET_DIR/denet-monitor.sh"
chmod +x "$DENET_DIR/denet-bot-listener.sh"
chmod +x "$DENET_DIR/denet-update.sh"
ok "Permissions set (chmod +x)"

# 4. Install cron job for monitor
CRON_JOB="*/5 * * * * $DENET_DIR/denet-monitor.sh"
if crontab -l 2>/dev/null | grep -q "denet-monitor.sh"; then
  warn "Cron job already exists — skipping."
else
  (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
  ok "Cron job installed: every 5 minutes"
fi

# 5. Install systemd service for bot listener
SERVICE_FILE="/etc/systemd/system/denet-bot.service"
CURRENT_USER=$(whoami)

info "Installing systemd service for bot listener..."
sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=DeNet Telegram Bot Listener
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${CURRENT_USER}
WorkingDirectory=${HOME}
ExecStart=${DENET_DIR}/denet-bot-listener.sh
Restart=always
RestartSec=10
StandardOutput=append:${DENODE_DIR}/bot-listener.log
StandardError=append:${DENODE_DIR}/bot-listener.log
Environment="DENODE_PASSWORD=YOUR_NODE_PASSWORD"

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable denet-bot
sudo systemctl start denet-bot
ok "Bot listener service installed and started"

# 6. Install denet-update as system command
info "Installing denet-update as system command..."
sudo cp "$DENET_DIR/denet-update.sh" /usr/local/bin/denet-update
sudo chmod +x /usr/local/bin/denet-update
ok "denet-update command available system-wide"

# 7. Fix log file ownership
sudo chown -R "$CURRENT_USER:$CURRENT_USER" "$DENODE_DIR" 2>/dev/null
ok "Log file ownership fixed"

# 8. Verify
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  Setup Complete! Verification${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${CYAN}Cron jobs:${NC}"
crontab -l | grep denet
echo ""
echo -e "${CYAN}Bot listener service:${NC}"
sudo systemctl status denet-bot --no-pager | head -5
echo ""
echo -e "${CYAN}denet-update command:${NC} $(which denet-update)"
echo ""
echo -e "${GREEN}${BOLD}All done! Check your Telegram — the bot should send a startup message.${NC}"
echo ""
echo -e "${YELLOW}Useful commands:${NC}"
echo "  sudo systemctl status denet-bot       — Check bot status"
echo "  sudo systemctl restart denet-bot      — Restart bot"
echo "  tail -f ~/.denode/bot-listener.log    — Watch bot logs"
echo "  tail -f ~/.denode/monitor.log         — Watch monitor logs"
echo "  denet-update --check                  — Check for new releases"
echo ""
=======

>>>>>>> ea719db645f5f3824483919fc75481022eac4da8
