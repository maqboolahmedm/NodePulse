#!/bin/bash

# ============================================================
# NodePulse IP Watch — Community Version (lsw)
# Monitors public IP changes and updates DuckDNS
# Runs every 15 min via cron
# ============================================================

TELEGRAM_BOT_TOKEN="YOUR_TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="YOUR_TELEGRAM_CHAT_ID"
DUCKDNS_TOKEN="YOUR_DUCKDNS_TOKEN"
DUCKDNS_DOMAIN="YOUR_DUCKDNS_DOMAIN"
LOCAL_TIMEZONE="YOUR_TIMEZONE"

IP_FILE="$HOME/.denode/.public_ip"
LOG_FILE="$HOME/.denode/ip-watch.log"

now_utc()   { date -u '+%Y-%m-%d %H:%M:%S UTC'; }
now_local() { TZ="${LOCAL_TIMEZONE}" date '+%H:%M:%S %Z'; }
log()       { echo "[$(now_utc) | $(now_local)] [IP-WATCH] $1" | tee -a "$LOG_FILE"; }

send_telegram() {
  curl -s --max-time 15 -X POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" -d text="${1}" \
    -d parse_mode="HTML" > /dev/null 2>&1
}

# Get current public IP
CURRENT_IP=$(curl -s --max-time 10 https://api.ipify.org 2>/dev/null)
if [ -z "$CURRENT_IP" ]; then
  CURRENT_IP=$(curl -s --max-time 10 https://icanhazip.com 2>/dev/null | tr -d '\n')
fi

if [ -z "$CURRENT_IP" ]; then
  log "❌ Could not determine public IP"
  exit 1
fi

# Compare with saved IP
SAVED_IP=""
[ -f "$IP_FILE" ] && SAVED_IP=$(cat "$IP_FILE")

if [ "$CURRENT_IP" = "$SAVED_IP" ]; then
  log "✅ IP unchanged: $CURRENT_IP"
  exit 0
fi

# IP changed!
log "🔄 IP changed: $SAVED_IP → $CURRENT_IP"
echo "$CURRENT_IP" > "$IP_FILE"

# Update DuckDNS
if [ -n "$DUCKDNS_TOKEN" ] && [ -n "$DUCKDNS_DOMAIN" ]; then
  RESULT=$(curl -s --max-time 10 \
    "https://www.duckdns.org/update?domains=${DUCKDNS_DOMAIN}&token=${DUCKDNS_TOKEN}&ip=${CURRENT_IP}")
  if [ "$RESULT" = "OK" ]; then
    log "✅ DuckDNS updated: ${DUCKDNS_DOMAIN}.duckdns.org → $CURRENT_IP"
    send_telegram "🌐 <b>NodePulse IP Watch</b>
🔄 Public IP changed!
📡 Old IP: <code>${SAVED_IP:-unknown}</code>
📡 New IP: <code>${CURRENT_IP}</code>
✅ DuckDNS updated: ${DUCKDNS_DOMAIN}.duckdns.org
🕐 $(now_utc) | $(now_local)"
  else
    log "⚠️ DuckDNS update failed: $RESULT"
    send_telegram "⚠️ <b>NodePulse IP Watch</b>
🔄 IP changed to <code>${CURRENT_IP}</code>
❌ DuckDNS update failed!
🕐 $(now_utc) | $(now_local)"
  fi
else
  send_telegram "🌐 <b>NodePulse IP Watch</b>
🔄 Public IP changed!
📡 New IP: <code>${CURRENT_IP}</code>
🕐 $(now_utc) | $(now_local)"
fi
