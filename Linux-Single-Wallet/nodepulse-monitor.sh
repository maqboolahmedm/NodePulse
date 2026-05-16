#!/bin/bash

# ============================================================
# NodePulse Monitor & Auto-Restart Script
# Linux Single-Wallet Version
# v3.2 — Added: pause check, tunnel health detection
# ============================================================

# --- Telegram Config ---
TELEGRAM_BOT_TOKEN="YOUR_TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="YOUR_TELEGRAM_CHAT_ID"

# --- DuckDNS Config ---
DUCKDNS_TOKEN="YOUR_DUCKDNS_TOKEN"
DUCKDNS_DOMAIN="YOUR_DUCKDNS_DOMAIN"

# --- Node Config ---
DENODE_BIN="/usr/bin/denode"
WALLET_ADDRESS="YOUR_WALLET_ADDRESS"
LICENSES=(YOUR_LICENSE_1 YOUR_LICENSE_2 YOUR_LICENSE_3 YOUR_LICENSE_4 YOUR_LICENSE_5 YOUR_LICENSE_6)

# Per-node ports
declare -A NODE_PORT
NODE_PORT[YOUR_LICENSE_1]=55050
NODE_PORT[YOUR_LICENSE_2]=55051
NODE_PORT[YOUR_LICENSE_3]=55052
NODE_PORT[YOUR_LICENSE_4]=55053
NODE_PORT[YOUR_LICENSE_5]=55054
NODE_PORT[YOUR_LICENSE_6]=55055

# Per-node private RPC endpoints
declare -A NODE_RPC
NODE_RPC[YOUR_LICENSE_1]="https://peaq.api.onfinality.io/rpc?apikey=YOUR_RPC_APIKEY_1"
NODE_RPC[YOUR_LICENSE_2]="https://peaq.api.onfinality.io/rpc?apikey=YOUR_RPC_APIKEY_2"
NODE_RPC[YOUR_LICENSE_3]="https://peaq.api.onfinality.io/rpc?apikey=YOUR_RPC_APIKEY_3"
NODE_RPC[YOUR_LICENSE_4]="https://peaq.api.onfinality.io/rpc?apikey=YOUR_RPC_APIKEY_4"
NODE_RPC[YOUR_LICENSE_5]="https://peaq.api.onfinality.io/rpc?apikey=YOUR_RPC_APIKEY_5"
NODE_RPC[YOUR_LICENSE_6]="https://peaq.api.onfinality.io/rpc?apikey=YOUR_RPC_APIKEY_6"

# Per-node storage paths
declare -A NODE_STORAGE
NODE_STORAGE[YOUR_LICENSE_1]="YOUR_STORAGE_PATH/YOUR_LICENSE_1"
NODE_STORAGE[YOUR_LICENSE_2]="YOUR_STORAGE_PATH/YOUR_LICENSE_2"
NODE_STORAGE[YOUR_LICENSE_3]="YOUR_STORAGE_PATH/YOUR_LICENSE_3"
NODE_STORAGE[YOUR_LICENSE_4]="YOUR_STORAGE_PATH/YOUR_LICENSE_4"
NODE_STORAGE[YOUR_LICENSE_5]="YOUR_STORAGE_PATH/YOUR_LICENSE_5"
NODE_STORAGE[YOUR_LICENSE_6]="YOUR_STORAGE_PATH/YOUR_LICENSE_6"

# --- Log Config ---
LOG_FILE="$HOME/.denode/monitor.log"
NODE_LOG_DIR="$HOME/.denode/logs"
HEARTBEAT_FILE="$HOME/.denode/.last_heartbeat"
DAILY_SUMMARY_FILE="$HOME/.denode/.last_daily_summary"
ERROR_STATE_FILE="$HOME/.denode/.last_error_state"
RESTART_COUNT_FILE="$HOME/.denode/.restart_counts"
PID_STATE_FILE="$HOME/.denode/.node_pids"
LAST_SEEN_FILE="$HOME/.denode/.node_last_seen"
DOWNTIME_LOG="$HOME/.denode/.node_downtime_log"
PENALTY_FILE="$HOME/.denode/.node_penalties"
STATUS_JSON="/var/www/html/nodepulse/status.json"
CHAIN_STATUS_FILE="$HOME/.denode/.chain_status"

# --- Pause/Stop support (set by bot /stop command) ---
GUARD_DIR="$HOME/.nodepulse_guard"
PAUSED_FILE="$GUARD_DIR/paused_nodes"

mkdir -p "$NODE_LOG_DIR" "$GUARD_DIR" "$(dirname $STATUS_JSON)" 2>/dev/null || true
touch "$PID_STATE_FILE" "$LAST_SEEN_FILE" "$DOWNTIME_LOG" "$PENALTY_FILE" "$PAUSED_FILE"

# --- Penalty Config ---
PENALTY_WARN=5
PENALTY_CRITICAL=8
PENALTY_MAX=10
CYCLE_MINUTES=90

# --- Disk Config ---
DISK_ALERT_THRESHOLD=85
STORAGE_DRIVES=(
  "YOUR_STORAGE_PATH/YOUR_LICENSE_1"
  "YOUR_STORAGE_PATH/YOUR_LICENSE_2"
  "YOUR_STORAGE_PATH/YOUR_LICENSE_3"
  "YOUR_STORAGE_PATH/YOUR_LICENSE_4"
  "YOUR_STORAGE_PATH/YOUR_LICENSE_5"
  "YOUR_STORAGE_PATH/YOUR_LICENSE_6"
)

# --- Daily Summary Config ---
DAILY_SUMMARY_HOUR=8

# --- Timezone Config ---
LOCAL_TIMEZONE="YOUR_TIMEZONE"

# --- Display ---
export DISPLAY=:0
export XAUTHORITY="$HOME/.Xauthority"
export DENODE_PASSWORD="YOUR_NODE_PASSWORD"

# --- Tunnel health: log silence threshold (seconds) ---
TUNNEL_SILENCE_THRESHOLD=600

# ============================================================
# Time Functions
# ============================================================
now_utc()  { date -u '+%Y-%m-%d %H:%M:%S UTC'; }
now_local(){ TZ="${LOCAL_TIMEZONE}" date '+%H:%M:%S %Z'; }
now_both() { echo "$(now_utc) | $(now_local)"; }

# ============================================================
# Core Functions
# ============================================================
log() { echo "[$(now_utc) | $(now_local)] $1" | tee -a "$LOG_FILE"; }

send_telegram() {
  local MESSAGE="$1"
  local RESPONSE
  RESPONSE=$(curl -s --max-time 15 -X POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    -d text="${MESSAGE}" \
    -d parse_mode="HTML" 2>&1)
  if echo "$RESPONSE" | grep -q '"ok":false'; then
    log "⚠️ Telegram API error: $RESPONSE"
  elif [ -z "$RESPONSE" ]; then
    log "⚠️ Telegram: No response (network issue?)"
  fi
}

is_node_running() {
  ps aux | grep -v grep | grep "$DENODE_BIN" | grep -- "--license $1" > /dev/null 2>&1
  return $?
}

get_node_pid() {
  ps aux | grep -v grep | grep "$DENODE_BIN" | grep -- "--license $1" | awk '{print $2}' | head -n 1
}

# ── Pause check — set by bot /stop command ──────────────────
is_paused() {
  grep -qx "$1" "$PAUSED_FILE" 2>/dev/null
}

# ============================================================
# Tunnel Health Check
# Checks two signals:
#   1. Is the node's port listening locally?
#   2. Has the log file been updated recently?
# If process is running but BOTH signals are dead → tunnel issue
# Returns: OK | NO_PORT | SILENT | DEAD
# ============================================================
check_tunnel_health() {
  local LICENSE="$1"
  local PORT="${NODE_PORT[$LICENSE]}"
  local LOG="$NODE_LOG_DIR/node-${LICENSE}.log"

  local PORT_OPEN=0
  local LOG_FRESH=0

  # Check if port is listening
  if [ -n "$PORT" ] && ss -tlnp 2>/dev/null | grep -q ":${PORT}"; then
    PORT_OPEN=1
  fi

  # Check log freshness
  if [ -f "$LOG" ]; then
    local LOG_AGE=$(( $(date +%s) - $(stat -c %Y "$LOG" 2>/dev/null || echo 0) ))
    [ "$LOG_AGE" -lt "$TUNNEL_SILENCE_THRESHOLD" ] && LOG_FRESH=1
  fi

  if [ "$PORT_OPEN" -eq 0 ] && [ "$LOG_FRESH" -eq 0 ]; then
    echo "DEAD"
  elif [ "$PORT_OPEN" -eq 0 ]; then
    echo "NO_PORT"
  elif [ "$LOG_FRESH" -eq 0 ]; then
    echo "SILENT"
  else
    echo "OK"
  fi
}

get_node_uptime() {
  local LICENSE="$1"
  local PID; PID=$(get_node_pid "$LICENSE")
  if [ -z "$PID" ]; then echo "not running"; return; fi
  local ETIME; ETIME=$(ps -o etime= -p "$PID" 2>/dev/null | tr -d ' ')
  if [ -z "$ETIME" ]; then echo "unknown"; return; fi
  local DAYS=0 HOURS=0 MINS=0 SECS=0
  if echo "$ETIME" | grep -q '-'; then
    DAYS=$(echo "$ETIME" | cut -d'-' -f1)
    ETIME=$(echo "$ETIME" | cut -d'-' -f2)
  fi
  local PARTS; IFS=':' read -ra PARTS <<< "$ETIME"
  case ${#PARTS[@]} in
    3) HOURS=${PARTS[0]}; MINS=${PARTS[1]}; SECS=${PARTS[2]} ;;
    2) MINS=${PARTS[0]}; SECS=${PARTS[1]} ;;
    1) SECS=${PARTS[0]} ;;
  esac
  DAYS=$((10#$DAYS)); HOURS=$((10#$HOURS)); MINS=$((10#$MINS))
  local RESULT=""
  [ "$DAYS"  -gt 0 ] && RESULT="${DAYS}d "
  [ "$HOURS" -gt 0 ] && RESULT="${RESULT}${HOURS}h "
  [ "$MINS"  -gt 0 ] && RESULT="${RESULT}${MINS}m"
  [ -z "$RESULT" ]   && RESULT="< 1m"
  echo "$RESULT"
}

restart_node() {
  local LICENSE="$1"
  local OLD_PID
  OLD_PID=$(get_node_pid "$LICENSE")
  [ -z "$OLD_PID" ] && OLD_PID=$(get_saved_pid "$LICENSE")

  local LAST_SEEN OFFLINE_DURATION WENT_DOWN_UTC
  LAST_SEEN=$(get_last_seen "$LICENSE")
  if [ -n "$LAST_SEEN" ]; then
    local NOW; NOW=$(date +%s)
    local OFFLINE_SECS=$(( NOW - LAST_SEEN ))
    OFFLINE_DURATION=$(format_duration "$OFFLINE_SECS")
    WENT_DOWN_UTC=$(date -u -d "@${LAST_SEEN}" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || \
                    date -u -r "$LAST_SEEN" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null)
  else
    OFFLINE_DURATION="unknown"; WENT_DOWN_UTC="unknown"
  fi

  log "Restarting node $LICENSE (last seen alive: ${WENT_DOWN_UTC}, offline ~${OFFLINE_DURATION})..."

  nohup "$DENODE_BIN" \
    --address "$WALLET_ADDRESS" \
    --license "$LICENSE" \
    >> "$NODE_LOG_DIR/node-${LICENSE}.log" 2>&1 &

  sleep 3

  if is_node_running "$LICENSE"; then
    local NEW_PID; NEW_PID=$(get_node_pid "$LICENSE")
    increment_restart_count "$LICENSE"
    local TOTAL_RESTARTS; TOTAL_RESTARTS=$(get_restart_count "$LICENSE")
    save_pid "$LICENSE" "$NEW_PID"
    update_last_seen "$LICENSE"
    echo "${LICENSE}|$(date -u '+%Y-%m-%d %H:%M:%S UTC')|${WENT_DOWN_UTC}|${OFFLINE_DURATION}|${OLD_PID:-unknown}|${NEW_PID}" >> "$DOWNTIME_LOG"
    log "✅ Node $LICENSE restarted (PID: $NEW_PID, offline ~${OFFLINE_DURATION}, Total restarts: $TOTAL_RESTARTS)"
    send_telegram "✅ <b>DeNet Node Restarted</b>
🔑 License: <code>${LICENSE}</code>
🆔 Old PID: <code>${OLD_PID:-unknown}</code> → New PID: <code>${NEW_PID}</code>
🔄 Total Restarts: <b>${TOTAL_RESTARTS}</b>
📅 Last seen alive: <b>${WENT_DOWN_UTC}</b>
⏱ Was offline for: <b>${OFFLINE_DURATION}</b>
🕐 $(now_utc)
🕐 $(now_local)
📍 Host: $(hostname)"
  else
    log "❌ Node $LICENSE FAILED to restart!"
    send_telegram "❌ <b>DeNet Node FAILED to Restart</b>
🔑 License: <code>${LICENSE}</code>
⚠️ Manual intervention required!
📅 Last seen alive: <b>${WENT_DOWN_UTC}</b>
⏱ Was offline for: <b>${OFFLINE_DURATION}</b>
🕐 $(now_utc)
🕐 $(now_local)
📍 Host: $(hostname)"
  fi
}

# ============================================================
# Restart Counter
# ============================================================
increment_restart_count() {
  local LICENSE="$1"
  local CURRENT; CURRENT=$(get_restart_count "$LICENSE")
  local NEW_COUNT=$(( CURRENT + 1 ))
  [ -f "$RESTART_COUNT_FILE" ] && sed -i "/^${LICENSE}=/d" "$RESTART_COUNT_FILE"
  echo "${LICENSE}=${NEW_COUNT}" >> "$RESTART_COUNT_FILE"
}

get_restart_count() {
  [ ! -f "$RESTART_COUNT_FILE" ] && echo "0" && return
  local COUNT; COUNT=$(grep "^${1}=" "$RESTART_COUNT_FILE" 2>/dev/null | cut -d= -f2)
  echo "${COUNT:-0}"
}

get_all_restart_counts() {
  local LINES=""
  for LIC in "${LICENSES[@]}"; do
    local COUNT; COUNT=$(get_restart_count "$LIC")
    local ICON="🟢"
    [ "$COUNT" -gt 0 ] && ICON="🔄"
    [ "$COUNT" -ge 5 ] && ICON="🔴"
    LINES="${LINES}${ICON} Node <code>${LIC}</code> — restarted <b>${COUNT}</b> time(s)\n"
  done
  echo -e "$LINES"
}

reset_restart_counts() { > "$RESTART_COUNT_FILE"; log "🔄 Restart counts reset."; }

# ============================================================
# PID Tracking & Downtime
# ============================================================
get_saved_pid()    { local V; V=$(grep "^${1}=" "$PID_STATE_FILE" 2>/dev/null | cut -d= -f2); echo "${V:-}"; }
save_pid()         { sed -i "/^${1}=/d" "$PID_STATE_FILE" 2>/dev/null; echo "${1}=${2}" >> "$PID_STATE_FILE"; }
update_last_seen() { local N; N=$(date +%s); sed -i "/^${1}=/d" "$LAST_SEEN_FILE" 2>/dev/null; echo "${1}=${N}" >> "$LAST_SEEN_FILE"; }
get_last_seen()    { local V; V=$(grep "^${1}=" "$LAST_SEEN_FILE" 2>/dev/null | cut -d= -f2); echo "${V:-}"; }

format_duration() {
  local SECS="$1"
  local DAYS=$(( SECS / 86400 )) HOURS=$(( (SECS % 86400) / 3600 )) MINS=$(( (SECS % 3600) / 60 ))
  local RESULT=""
  [ "$DAYS"  -gt 0 ] && RESULT="${DAYS}d "
  [ "$HOURS" -gt 0 ] && RESULT="${RESULT}${HOURS}h "
  RESULT="${RESULT}${MINS}m"
  echo "$RESULT"
}

record_downtime_event() {
  local LICENSE="$1" OLD_PID="$2" NEW_PID="$3"
  local LAST_SEEN; LAST_SEEN=$(get_last_seen "$LICENSE")
  local NOW; NOW=$(date +%s)
  local WENT_DOWN_UTC="unknown" DOWNTIME_DURATION="unknown"
  if [ -n "$LAST_SEEN" ]; then
    WENT_DOWN_UTC=$(date -u -d "@${LAST_SEEN}" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || \
                    date -u -r "$LAST_SEEN" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null)
    DOWNTIME_DURATION=$(format_duration $(( NOW - LAST_SEEN )))
  fi
  echo "${LICENSE}|$(date -u '+%Y-%m-%d %H:%M:%S UTC')|${WENT_DOWN_UTC}|${DOWNTIME_DURATION}|${OLD_PID}|${NEW_PID}" >> "$DOWNTIME_LOG"
  echo "$WENT_DOWN_UTC|$DOWNTIME_DURATION"
}

check_pid_change() {
  local LICENSE="$1"
  local CURRENT_PID; CURRENT_PID=$(get_node_pid "$LICENSE")
  local SAVED_PID;   SAVED_PID=$(get_saved_pid "$LICENSE")
  if [ -n "$SAVED_PID" ] && [ -n "$CURRENT_PID" ] && [ "$SAVED_PID" != "$CURRENT_PID" ]; then
    local INFO; INFO=$(record_downtime_event "$LICENSE" "$SAVED_PID" "$CURRENT_PID")
    local WENT_DOWN; WENT_DOWN=$(echo "$INFO" | cut -d'|' -f1)
    local DURATION;  DURATION=$(echo "$INFO"  | cut -d'|' -f2)
    echo "RESTARTED|${SAVED_PID}|${CURRENT_PID}|${WENT_DOWN}|${DURATION}"
  else
    echo "OK"
  fi
}

# ============================================================
# Penalty Tracking
# ============================================================
get_penalty_count() { local V; V=$(grep "^${1}=" "$PENALTY_FILE" 2>/dev/null | cut -d= -f2); echo "${V:-0}"; }
set_penalty_count() { sed -i "/^${1}=/d" "$PENALTY_FILE" 2>/dev/null; echo "${1}=${2}" >> "$PENALTY_FILE"; }
increment_penalty() { local N=$(( $(get_penalty_count "$1") + 1 )); set_penalty_count "$1" "$N"; echo "$N"; }
reset_penalty()     { set_penalty_count "$1" "0"; log "✅ Node $1 penalties reset to 0 (successful proof cycle)"; }

check_proof_status() {
  local LICENSE="$1"
  local LOG_A="$NODE_LOG_DIR/license-${LICENSE}.log"
  local LOG_B="$NODE_LOG_DIR/node-${LICENSE}.log"
  local NODE_LOG=""
  [ -f "$LOG_A" ] && NODE_LOG="$LOG_A" || { [ -f "$LOG_B" ] && NODE_LOG="$LOG_B"; }
  [ -z "$NODE_LOG" ] && echo "UNKNOWN" && return
  local RECENT; RECENT=$(tail -100 "$NODE_LOG" 2>/dev/null)
  echo "$RECENT" | grep -qiE "proof sent|proof submitted|storage proof|proof_of_storage|sendProof|proofsent" && echo "PROOF_OK" && return
  echo "$RECENT" | grep -qiE "missed|penalty|failed to send proof|proof failed|deadline exceeded"            && echo "MISSED"   && return
  echo "UNKNOWN"
}

check_and_update_penalties() {
  local LICENSE="$1"
  is_node_running "$LICENSE" || return
  local PROOF_STATUS; PROOF_STATUS=$(check_proof_status "$LICENSE")
  local CURRENT_PENALTIES; CURRENT_PENALTIES=$(get_penalty_count "$LICENSE")
  if [ "$PROOF_STATUS" = "PROOF_OK" ]; then
    if [ "$CURRENT_PENALTIES" -gt 0 ]; then
      reset_penalty "$LICENSE"
      send_telegram "✅ <b>Node ${LICENSE} — Penalties Reset</b>
🔑 License: <code>${LICENSE}</code>
📊 Previous penalties: <b>${CURRENT_PENALTIES}</b> → Now: <b>0</b>
✅ Proof submitted successfully — cycle reset
🕐 $(now_utc) | $(now_local)
📍 Host: $(hostname)"
    fi
    return
  fi
  if [ "$PROOF_STATUS" = "MISSED" ]; then
    local NEW_PENALTIES; NEW_PENALTIES=$(increment_penalty "$LICENSE")
    log "⚠️ Node $LICENSE missed proof cycle — penalties: ${NEW_PENALTIES}/${PENALTY_MAX}"
    if [ "$NEW_PENALTIES" -eq "$PENALTY_WARN" ]; then
      send_telegram "⚠️ <b>Node ${LICENSE} — Penalty Warning</b>
🔑 License: <code>${LICENSE}</code>
📊 Penalties: <b>${NEW_PENALTIES}/${PENALTY_MAX}</b>
⏱ ~$(( (PENALTY_MAX - NEW_PENALTIES) * CYCLE_MINUTES / 60 ))h before pool removal
💡 Monitor closely — if next cycle fails, penalties increase
🕐 $(now_utc) | $(now_local)
📍 Host: $(hostname)"
    elif [ "$NEW_PENALTIES" -ge "$PENALTY_CRITICAL" ] && [ "$NEW_PENALTIES" -lt "$PENALTY_MAX" ]; then
      send_telegram "🚨 <b>Node ${LICENSE} — CRITICAL Penalty Alert</b>
🔑 License: <code>${LICENSE}</code>
📊 Penalties: <b>${NEW_PENALTIES}/${PENALTY_MAX}</b>
⚠️ Only $(( PENALTY_MAX - NEW_PENALTIES )) cycle(s) before pool removal!
🔄 Consider restarting node now
🕐 $(now_utc) | $(now_local)
📍 Host: $(hostname)"
    elif [ "$NEW_PENALTIES" -ge "$PENALTY_MAX" ]; then
      send_telegram "🚫 <b>Node ${LICENSE} — REMOVED FROM POOL</b>
🔑 License: <code>${LICENSE}</code>
📊 Penalties reached: <b>${NEW_PENALTIES}/${PENALTY_MAX}</b>
🔄 Restarting node — will auto re-join pool...
🕐 $(now_utc) | $(now_local)
📍 Host: $(hostname)"
      local OLD_PID; OLD_PID=$(get_node_pid "$LICENSE")
      [ -n "$OLD_PID" ] && kill "$OLD_PID" 2>/dev/null && sleep 2
      restart_node "$LICENSE"
      set_penalty_count "$LICENSE" "0"
    fi
  fi
}

get_penalty_summary() {
  local LINES=""
  for LIC in "${LICENSES[@]}"; do
    local COUNT; COUNT=$(get_penalty_count "$LIC")
    local ICON="🟢"
    [ "$COUNT" -ge "$PENALTY_WARN" ]     && ICON="🟡"
    [ "$COUNT" -ge "$PENALTY_CRITICAL" ] && ICON="🟠"
    LINES="${LINES}${ICON} Node <code>${LIC}</code> — <b>${COUNT}/${PENALTY_MAX}</b> penalties\n"
  done
  echo -e "$LINES"
}

# ============================================================
# DuckDNS
# ============================================================
update_duckdns() {
  local RESULT
  RESULT=$(curl -s --max-time 10 \
    "https://www.duckdns.org/update?domains=${DUCKDNS_DOMAIN}&token=${DUCKDNS_TOKEN}&ip=")
  [ "$RESULT" = "OK" ] && log "🌐 DuckDNS updated successfully." || log "⚠️ DuckDNS update failed: $RESULT"
}

# ============================================================
# Disk Monitoring
# ============================================================
check_disk_space() {
  for DRIVE in "${STORAGE_DRIVES[@]}"; do
    if [ ! -d "$DRIVE" ]; then
      log "⚠️ Drive $DRIVE not found or not mounted!"
      send_telegram "⚠️ <b>DeNet Drive Not Mounted</b>
💾 Drive: <code>${DRIVE}</code>
🕐 $(now_utc)
🕐 $(now_local)
📍 Host: $(hostname)
<i>Check if the drive is connected and mounted correctly.</i>"
      continue
    fi
    local USAGE TOTAL USED FREE
    USAGE=$(df "$DRIVE" | awk 'NR==2 {gsub("%",""); print $5}')
    TOTAL=$(df -h "$DRIVE" | awk 'NR==2 {print $2}')
    USED=$(df -h  "$DRIVE" | awk 'NR==2 {print $3}')
    FREE=$(df -h  "$DRIVE" | awk 'NR==2 {print $4}')
    log "💾 $DRIVE — ${USAGE}% used (${USED}/${TOTAL}, free: ${FREE})"
    if [ "$USAGE" -ge "$DISK_ALERT_THRESHOLD" ]; then
      log "⚠️ Drive $DRIVE at ${USAGE}% — exceeds threshold!"
      send_telegram "⚠️ <b>DeNet Drive Space Warning</b>
💾 Drive: <code>${DRIVE}</code>
📊 Usage: <b>${USAGE}%</b> (threshold: ${DISK_ALERT_THRESHOLD}%)
📦 Used: ${USED} / ${TOTAL}
🆓 Free: ${FREE}
🕐 $(now_utc)
🕐 $(now_local)
📍 Host: $(hostname)"
    fi
  done
}

get_disk_summary() {
  local SUMMARY=""
  for DRIVE in "${STORAGE_DRIVES[@]}"; do
    if [ ! -d "$DRIVE" ]; then
      SUMMARY="${SUMMARY}❌ $(basename $DRIVE) — NOT MOUNTED\n"; continue
    fi
    local USAGE USED TOTAL FREE
    USAGE=$(df "$DRIVE" | awk 'NR==2 {gsub("%",""); print $5}')
    USED=$(df -h  "$DRIVE" | awk 'NR==2 {print $3}')
    TOTAL=$(df -h "$DRIVE" | awk 'NR==2 {print $2}')
    FREE=$(df -h  "$DRIVE" | awk 'NR==2 {print $4}')
    local ICON="🟢"; [ "$USAGE" -ge "$DISK_ALERT_THRESHOLD" ] && ICON="🔴"
    SUMMARY="${SUMMARY}${ICON} $(basename $DRIVE): ${USAGE}% — ${USED}/${TOTAL} (free: ${FREE})\n"
  done
  echo -e "$SUMMARY"
}

# ============================================================
# Error Alerts
# ============================================================
ERROR_PATTERNS=(
  "roothash mismatch|Roothash Mismatch"
  "context deadline exceeded|Transaction Timeout"
  "failed to unlock account|Password/Unlock Error"
  "already known|Duplicate Transaction"
  "connection refused|RPC Connection Refused"
  "i/o timeout|Network I/O Timeout"
)

check_node_errors() {
  local LICENSE="$1"
  local LOG_A="$NODE_LOG_DIR/license-${LICENSE}.log"
  local LOG_B="$NODE_LOG_DIR/node-${LICENSE}.log"
  local NODE_LOG=""
  [ -f "$LOG_A" ] && NODE_LOG="$LOG_A" || { [ -f "$LOG_B" ] && NODE_LOG="$LOG_B"; }
  [ -z "$NODE_LOG" ] && return
  local RECENT_LINES; RECENT_LINES=$(tail -50 "$NODE_LOG" 2>/dev/null)
  for PATTERN_ENTRY in "${ERROR_PATTERNS[@]}"; do
    local PATTERN="${PATTERN_ENTRY%%|*}" LABEL="${PATTERN_ENTRY##*|}"
    if echo "$RECENT_LINES" | grep -qi "$PATTERN"; then
      local STATE_KEY="${LICENSE}_${PATTERN// /_}"
      local LAST_ALERTED=""
      [ -f "$ERROR_STATE_FILE" ] && LAST_ALERTED=$(grep "^${STATE_KEY}=" "$ERROR_STATE_FILE" 2>/dev/null | cut -d= -f2)
      local NOW; NOW=$(date +%s)
      if [ -z "$LAST_ALERTED" ] || [ $(( NOW - LAST_ALERTED )) -ge 3600 ]; then
        local ERROR_LINE; ERROR_LINE=$(echo "$RECENT_LINES" | grep -i "$PATTERN" | tail -1)
        log "⚠️ Node $LICENSE — $LABEL detected"
        send_telegram "⚠️ <b>DeNet Node Error Detected</b>
🔑 License: <code>${LICENSE}</code>
🔴 Error: <b>${LABEL}</b>
📋 Detail: <code>${ERROR_LINE}</code>
🕐 $(now_utc)
🕐 $(now_local)
📍 Host: $(hostname)
<i>Node process is still running. This may auto-resolve.</i>"
        sed -i "/^${STATE_KEY}=/d" "$ERROR_STATE_FILE" 2>/dev/null
        echo "${STATE_KEY}=${NOW}" >> "$ERROR_STATE_FILE"
      fi
    fi
  done
}

# ============================================================
# Daily Summary
# ============================================================
send_daily_summary() {
  local STATUS_LINES="" UP_COUNT=0 DOWN_COUNT=0
  for LICENSE in "${LICENSES[@]}"; do
    if is_node_running "$LICENSE"; then
      local PID; PID=$(get_node_pid "$LICENSE")
      local UPTIME; UPTIME=$(get_node_uptime "$LICENSE")
      STATUS_LINES="${STATUS_LINES}🟢 <code>${LICENSE}</code> — PID <code>${PID}</code> — Up: <b>${UPTIME}</b>\n"
      UP_COUNT=$(( UP_COUNT + 1 ))
    else
      STATUS_LINES="${STATUS_LINES}🔴 <code>${LICENSE}</code> — DOWN\n"
      DOWN_COUNT=$(( DOWN_COUNT + 1 ))
    fi
  done
  local DISK_INFO; DISK_INFO=$(get_disk_summary)
  local OVERALL
  [ "$DOWN_COUNT" -eq 0 ] && OVERALL="✅ All 6 nodes healthy" || OVERALL="⚠️ ${DOWN_COUNT} node(s) are DOWN"
  send_telegram "📊 <b>DeNet Daily Summary Report</b>
📅 $(now_utc)
📅 $(now_local)
📍 Host: $(hostname)
<b>Node Status (${UP_COUNT}/6 online):</b>
$(echo -e "$STATUS_LINES")
<b>Overall:</b> ${OVERALL}
💾 <b>Disk Usage:</b>
$(echo -e "$DISK_INFO")
🔄 <b>Restart Counts (all-time):</b>
$(get_all_restart_counts)
<i>Next report tomorrow at ${DAILY_SUMMARY_HOUR}:00 AM local time</i>"
  log "📊 Daily summary sent to Telegram."
  date +%s > "$DAILY_SUMMARY_FILE"
}

should_send_daily_summary() {
  local CURRENT_HOUR
  CURRENT_HOUR=$((10#$(TZ="${LOCAL_TIMEZONE}" date '+%H')))
  [ "$CURRENT_HOUR" -ne "$DAILY_SUMMARY_HOUR" ] && return 1
  [ ! -f "$DAILY_SUMMARY_FILE" ] && return 0
  local LAST NOW DIFF
  LAST=$(cat "$DAILY_SUMMARY_FILE"); NOW=$(date +%s); DIFF=$(( NOW - LAST ))
  [ "$DIFF" -lt 82800 ] && return 1
  return 0
}

# ============================================================
# Heartbeat
# ============================================================
send_heartbeat() {
  local STATUS_LINES="" RESTART_ALERT_LINES="" HAS_RESTART_ALERT=0
  for LICENSE in "${LICENSES[@]}"; do
    if is_node_running "$LICENSE"; then
      local PID; PID=$(get_node_pid "$LICENSE")
      local UPTIME; UPTIME=$(get_node_uptime "$LICENSE")
      local RC; RC=$(get_restart_count "$LICENSE")
      local PID_CHECK; PID_CHECK=$(check_pid_change "$LICENSE")
      local PAUSE_TAG=""
      is_paused "$LICENSE" && PAUSE_TAG=" 🛑PAUSED"
      if [ "$PID_CHECK" != "OK" ]; then
        local OLD_PID WENT_DOWN OFFLINE_DURATION
        OLD_PID=$(echo "$PID_CHECK"         | cut -d'|' -f2)
        WENT_DOWN=$(echo "$PID_CHECK"       | cut -d'|' -f4)
        OFFLINE_DURATION=$(echo "$PID_CHECK"| cut -d'|' -f5)
        local PENALTIES; PENALTIES=$(get_penalty_count "$LICENSE")
        STATUS_LINES="${STATUS_LINES}⚠️ <code>${LICENSE}</code> — PID <code>${PID}</code> — Up: <b>${UPTIME}</b> — Restarts: <b>${RC}</b> — Penalties: <b>${PENALTIES}/${PENALTY_MAX}</b>${PAUSE_TAG}\n"
        RESTART_ALERT_LINES="${RESTART_ALERT_LINES}⚠️ Node <code>${LICENSE}</code> was restarted silently!\n"
        RESTART_ALERT_LINES="${RESTART_ALERT_LINES} 🔴 Old PID: <code>${OLD_PID}</code> → 🟢 New PID: <code>${PID}</code>\n"
        RESTART_ALERT_LINES="${RESTART_ALERT_LINES} 📅 Last seen alive: <b>${WENT_DOWN}</b>\n"
        RESTART_ALERT_LINES="${RESTART_ALERT_LINES} ⏱ Was offline for: <b>${OFFLINE_DURATION}</b>\n"
        HAS_RESTART_ALERT=1
        log "⚠️ PID change detected for node $LICENSE: $OLD_PID → $PID (offline ~${OFFLINE_DURATION})"
      else
        local PENALTIES; PENALTIES=$(get_penalty_count "$LICENSE")
        local PENALTY_ICON="🟢"
        [ "$PENALTIES" -ge "$PENALTY_WARN" ]     && PENALTY_ICON="🟡"
        [ "$PENALTIES" -ge "$PENALTY_CRITICAL" ] && PENALTY_ICON="🟠"
        STATUS_LINES="${STATUS_LINES}🟢 <code>${LICENSE}</code> — PID <code>${PID}</code> — Up: <b>${UPTIME}</b> — Restarts: <b>${RC}</b> — ${PENALTY_ICON} Penalties: <b>${PENALTIES}/${PENALTY_MAX}</b>${PAUSE_TAG}\n"
      fi
      save_pid "$LICENSE" "$PID"
      update_last_seen "$LICENSE"
    else
      local RC; RC=$(get_restart_count "$LICENSE")
      local PAUSE_TAG=""
      is_paused "$LICENSE" && PAUSE_TAG=" 🛑PAUSED"
      STATUS_LINES="${STATUS_LINES}🔴 <code>${LICENSE}</code> — <b>DOWN</b> — Restarts: <b>${RC}</b>${PAUSE_TAG}\n"
    fi
  done
  local DISK_INFO; DISK_INFO=$(get_disk_summary)
  local RESTART_SECTION=""
  [ "$HAS_RESTART_ALERT" -eq 1 ] && RESTART_SECTION="
⚠️ <b>Silent Restart Detected:</b>
$(echo -e "$RESTART_ALERT_LINES")"
  send_telegram "💓 <b>DeNet Node Monitor HeartBeat</b>
📍 Host: $(hostname)
🕐 $(now_utc)
🕐 $(now_local)
${RESTART_SECTION}
<b>Node Status:</b>
$(echo -e "$STATUS_LINES")
💾 <b>Disk:</b>
$(echo -e "$DISK_INFO")"
  log "💓 Heartbeat sent to Telegram."
  date +%s > "$HEARTBEAT_FILE"
}

should_send_heartbeat() {
  local INTERVAL=3600
  [ ! -f "$HEARTBEAT_FILE" ] && return 0
  local LAST NOW DIFF
  LAST=$(cat "$HEARTBEAT_FILE"); NOW=$(date +%s); DIFF=$(( NOW - LAST ))
  [ "$DIFF" -ge "$INTERVAL" ] && return 0
  return 1
}

# ============================================================
# Chain Status (from node logs)
# ============================================================
check_chain_status_from_logs() {
  log "⛓ Checking on-chain status from node logs..."
  python3 - <<CHAINEOF
import os, re, json, subprocess
from datetime import datetime, timezone, timedelta

licenses = [$(printf '"%s",' "${LICENSES[@]}" | sed 's/,$//')]
log_dir  = os.path.expanduser("$NODE_LOG_DIR")
now_utc  = datetime.now(timezone.utc)
results  = {}

PROOF_OK_PATTERN   = re.compile(r'Proof of Storage stage handling completed|Collect Proofs handling completed', re.IGNORECASE)
PROOF_FAIL_PATTERN = re.compile(r'Failed to send proof|failed to submit', re.IGNORECASE)
STAGE_PATTERN      = re.compile(r'Current Stage:\s*(\w[\w ]+\w)', re.IGNORECASE)
POOL_PATTERN       = re.compile(r'License ID is in (\d+) pool', re.IGNORECASE)
TIMESTAMP_PATTERN  = re.compile(r'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})')

def parse_log_timestamp(line):
    m = TIMESTAMP_PATTERN.search(line)
    if not m: return None
    try:
        dt_naive = datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S")
        result = subprocess.run(
            ['date', '-d', f'TZ="$LOCAL_TIMEZONE" {m.group(1)}', '+%s'],
            capture_output=True, text=True, shell=False
        )
        if result.returncode == 0 and result.stdout.strip():
            return datetime.fromtimestamp(int(result.stdout.strip()), tz=timezone.utc)
        ist_offset = timedelta(hours=5, minutes=30)
        dt_ist = dt_naive.replace(tzinfo=timezone(ist_offset))
        return dt_ist.astimezone(timezone.utc)
    except: pass
    return None

for lic in licenses:
    log_a    = os.path.join(log_dir, f"node-{lic}.log")
    log_b    = os.path.join(log_dir, f"license-{lic}.log")
    log_file = log_a if os.path.exists(log_a) else (log_b if os.path.exists(log_b) else None)
    if not log_file:
        results[str(lic)] = {"status": "unknown", "reason": "no log file", "last_proof": "", "pool": "", "last_error": ""}
        continue
    try:
        with open(log_file, 'rb') as f:
            f.seek(0, 2); size = f.tell()
            f.seek(max(0, size - 102400))
            lines = f.read().decode('utf-8', errors='ignore').splitlines()
    except Exception as e:
        results[str(lic)] = {"status": "unknown", "reason": str(e), "last_proof": "", "pool": "", "last_error": ""}
        continue

    last_proof_time = None; last_error_time = None; last_error_msg = ""
    current_stage = ""; pool_number = ""; last_ts = None

    for line in reversed(lines):
        ts = parse_log_timestamp(line)
        if ts and last_ts is None: last_ts = ts
        if not pool_number:
            m = POOL_PATTERN.search(line)
            if m: pool_number = m.group(1)
        if not current_stage:
            m = STAGE_PATTERN.search(line)
            if m: current_stage = m.group(1).strip()
        if last_proof_time is None and PROOF_OK_PATTERN.search(line):
            last_proof_time = ts or last_ts
        if last_error_time is None and PROOF_FAIL_PATTERN.search(line):
            last_error_time = ts or last_ts; last_error_msg = line.strip()[:120]
        if last_proof_time and pool_number and current_stage: break

    if last_proof_time:
        age_min    = (now_utc - last_proof_time).total_seconds() / 60
        status     = "online" if age_min < 95 else ("pending" if age_min < 190 else "offline")
        last_proof_str = last_proof_time.strftime("%Y-%m-%d %H:%M UTC")
        age_str    = f"{int(age_min)}m ago" if age_min < 60 else f"{age_min/60:.1f}h ago"
    else:
        status = "unknown"; last_proof_str = "No proof found in recent logs"; age_str = "unknown"

    results[str(lic)] = {"status": status, "last_proof": last_proof_str,
                          "age": age_str, "pool": pool_number,
                          "stage": current_stage, "last_error": last_error_msg}
    print(f"[{lic}] {status.upper()} | Pool: {pool_number} | Stage: {current_stage} | Last proof: {age_str}")

out = {"fetched_at": now_utc.strftime("%Y-%m-%d %H:%M:%S UTC"), "source": "node_logs", "nodes": results}
with open(os.path.expanduser("$CHAIN_STATUS_FILE"), 'w') as f:
    json.dump(out, f, indent=2)
print("Chain status saved ✅")
CHAINEOF
  log "⛓ Chain status updated from node logs."
}

should_check_chain_status() {
  [ ! -f "$CHAIN_STATUS_FILE" ] && return 0
  local LAST NOW DIFF
  LAST=$(python3 -c "
import json
try:
    d=json.load(open('$CHAIN_STATUS_FILE'))
    from datetime import datetime,timezone
    ft=d.get('fetched_at','')
    if ft:
        dt=datetime.strptime(ft,'%Y-%m-%d %H:%M:%S UTC').replace(tzinfo=timezone.utc)
        print(int(dt.timestamp()))
    else: print(0)
except: print(0)
" 2>/dev/null || echo 0)
  NOW=$(date +%s); DIFF=$(( NOW - LAST ))
  [ "$DIFF" -ge 300 ] && return 0
  return 1
}

# ============================================================
# Write status.json
# ============================================================
write_status_json() {
  local DENODE_VERSION
  DENODE_VERSION=$("$DENODE_BIN" --version 2>/dev/null | head -1 || echo "unknown")

  python3 - <<PYEOF
import json, os, subprocess
from datetime import datetime, timezone

licenses    = [$(printf '"%s",' "${LICENSES[@]}" | sed 's/,$//')]
pid_file    = os.path.expanduser("$PID_STATE_FILE")
seen_file   = os.path.expanduser("$LAST_SEEN_FILE")
rc_file     = os.path.expanduser("$RESTART_COUNT_FILE")
dt_log      = os.path.expanduser("$DOWNTIME_LOG")
pen_file    = os.path.expanduser("$PENALTY_FILE")
penalty_max = int("$PENALTY_MAX")
drives      = [$(printf '"%s",' "${STORAGE_DRIVES[@]}" | sed 's/,$//')]
guard_dir   = os.path.expanduser("~/.nodepulse_guard")
paused_file = os.path.expanduser("$PAUSED_FILE")

def read_kv(path):
    out = {}
    try:
        for line in open(path):
            if "=" in line:
                k, v = line.strip().split("=", 1)
                out[k] = v
    except: pass
    return out

def read_paused():
    try:
        return set(open(paused_file).read().splitlines())
    except: return set()

saved_pids  = read_kv(pid_file)
last_seen   = read_kv(seen_file)
restart_cnt = read_kv(rc_file)
penalties   = read_kv(pen_file)
paused_set  = read_paused()

def get_score(lic):
    try:
        with open(os.path.join(guard_dir, "score_" + str(lic))) as f:
            return max(0, min(100, int(f.read().strip())))
    except: return None

def get_tunnel_status(lic):
    try:
        with open(os.path.join(guard_dir, "tunnel_" + str(lic))) as f:
            return f.read().strip()
    except: return None

def get_last_downtime(lic):
    try:
        lines = [l for l in open(dt_log) if l.startswith(str(lic)+"|")]
        if not lines: return None
        parts = lines[-1].strip().split("|")
        return {"restarted_at": parts[1], "last_alive": parts[2],
                "offline_duration": parts[3], "old_pid": parts[4], "new_pid": parts[5]}
    except: return None

def get_ps_info(lic):
    try:
        r = subprocess.run(["ps", "aux"], capture_output=True, text=True)
        for line in r.stdout.splitlines():
            if "/usr/bin/denode" in line and f"--license {lic}" in line and "grep" not in line:
                parts = line.split()
                pid   = parts[1]
                r2    = subprocess.run(["ps", "-o", "etime=", "-p", pid], capture_output=True, text=True)
                etime = r2.stdout.strip()
                return pid, etime
    except: pass
    return None, None

def parse_etime(et):
    if not et: return "unknown"
    days, hours, mins = 0, 0, 0
    if "-" in et:
        days, et = et.split("-", 1); days = int(days)
    parts = et.split(":")
    if len(parts) == 3: hours, mins = int(parts[0]), int(parts[1])
    elif len(parts) == 2: mins = int(parts[0])
    r = ""
    if days:  r += f"{days}d "
    if hours: r += f"{hours}h "
    r += f"{mins}m"
    return r.strip() or "< 1m"

def get_disk(drive):
    try:
        r = subprocess.run(["df", "-h", drive], capture_output=True, text=True)
        parts = r.stdout.splitlines()[1].split()
        pct   = int(parts[4].replace("%",""))
        return {"used": parts[2], "total": parts[1], "free": parts[3], "pct": pct}
    except: return None

now_ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

storage_paths = {$(for L in "${LICENSES[@]}"; do echo "\"${L}\": \"${NODE_STORAGE[$L]}\","; done)}

nodes  = []
for lic in licenses:
    pid, etime  = get_ps_info(lic)
    running     = pid is not None
    saved_pid   = saved_pids.get(str(lic), "")
    pid_changed = saved_pid and pid and saved_pid != pid
    ls_ts       = last_seen.get(str(lic), "")
    last_seen_str = ""
    if ls_ts:
        try:
            dt = datetime.fromtimestamp(int(ls_ts), tz=timezone.utc)
            last_seen_str = dt.strftime("%Y-%m-%d %H:%M:%S UTC")
        except: pass
    disk = get_disk(storage_paths.get(str(lic), ""))
    nodes.append({
        "license":       lic,
        "status":        "running" if running else "down",
        "paused":        str(lic) in paused_set,
        "pid":           pid or "",
        "uptime":        parse_etime(etime) if running else "",
        "restarts":      int(restart_cnt.get(str(lic), 0)),
        "penalties":     int(penalties.get(str(lic), 0)),
        "penalty_max":   penalty_max,
        "pid_changed":   bool(pid_changed),
        "old_pid":       saved_pid if pid_changed else "",
        "last_seen":     last_seen_str,
        "last_downtime": get_last_downtime(lic),
        "disk":          disk,
        "score":         get_score(lic),
        "tunnel":        get_tunnel_status(lic),
    })

data = {
    "app":          "NodePulse",
    "version":      "${DENODE_VERSION}",
    "host":         "$(hostname)",
    "updated":      now_ts,
    "nodes":        nodes,
    "chain_status": json.load(open(os.path.expanduser("$CHAIN_STATUS_FILE"))) if os.path.exists(os.path.expanduser("$CHAIN_STATUS_FILE")) else None
}

out = "$STATUS_JSON"
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w") as f:
    json.dump(data, f, indent=2)
print(f"status.json written → {out}")
PYEOF
  log "📡 status.json updated for NodePulse."
}

# ============================================================
# Main Monitor Loop
# ============================================================
log "========== DeNet Monitor Run Started =========="

DOWN_COUNT=0

# 1. Update DuckDNS
update_duckdns

# 2. Check node processes
for LICENSE in "${LICENSES[@]}"; do

  # ── PAUSE CHECK ────────────────────────────────────────────
  if is_paused "$LICENSE"; then
    log "⏸️  Node $LICENSE is PAUSED — skipping all checks"
    continue
  fi
  # ──────────────────────────────────────────────────────────

  if is_node_running "$LICENSE"; then
    PID=$(get_node_pid "$LICENSE")
    UPTIME=$(get_node_uptime "$LICENSE")
    log "✅ Node $LICENSE is running (PID: $PID, Uptime: $UPTIME)"
    save_pid "$LICENSE" "$PID"
    update_last_seen "$LICENSE"

    # ── TUNNEL HEALTH CHECK ──────────────────────────────────
    TUNNEL=$(check_tunnel_health "$LICENSE")
    echo "$TUNNEL" > "$GUARD_DIR/tunnel_${LICENSE}"
    case "$TUNNEL" in
      DEAD)
        log "🔌 Node $LICENSE — process running but tunnel appears DEAD (port closed + log silent)"
        send_telegram "🔌 <b>Node ${LICENSE} — Tunnel Dead</b>
🔑 License: <code>${LICENSE}</code>
⚠️ Process is running but port is closed and log is silent
🔄 Restarting to re-establish tunnel...
🕐 $(now_utc) | $(now_local)
📍 Host: $(hostname)"
        OLD_PID=$(get_node_pid "$LICENSE")
        [ -n "$OLD_PID" ] && kill "$OLD_PID" 2>/dev/null && sleep 2
        restart_node "$LICENSE"
        ;;
      NO_PORT)
        log "🔌 Node $LICENSE — port not listening (log still active — may be re-tunneling)"
        ;;
      SILENT)
        log "⚠️ Node $LICENSE — log silent >$((TUNNEL_SILENCE_THRESHOLD/60))min (port open — monitoring)"
        ;;
      OK)
        log "🔗 Node $LICENSE — tunnel OK (port open + log active)"
        ;;
    esac
    # ─────────────────────────────────────────────────────────

  else
    log "⚠️  Node $LICENSE is DOWN — attempting restart..."
    DOWN_COUNT=$(( DOWN_COUNT + 1 ))
    send_telegram "⚠️ <b>DeNet Node Down Detected</b>
🔑 License: <code>${LICENSE}</code>
🔄 Attempting restart...
🕐 $(now_utc)
🕐 $(now_local)
📍 Host: $(hostname)"
    restart_node "$LICENSE"
  fi
done

[ "$DOWN_COUNT" -eq 0 ] && log "All nodes running normally." || log "$DOWN_COUNT node(s) were restarted."

# 3. Check disk space
check_disk_space

# 4. Check node logs for errors
log "--- Checking node logs for errors ---"
for LICENSE in "${LICENSES[@]}"; do
  is_paused "$LICENSE" && continue
  check_node_errors "$LICENSE"
done

# 5. Check and update penalties
log "--- Checking proof cycles and penalties ---"
for LICENSE in "${LICENSES[@]}"; do
  is_paused "$LICENSE" && continue
  check_and_update_penalties "$LICENSE"
  PENALTIES=$(get_penalty_count "$LICENSE")
  log "📊 Node $LICENSE — penalties: ${PENALTIES}/${PENALTY_MAX}"
done

# 6. Check blockchain status from node logs
if should_check_chain_status; then
  check_chain_status_from_logs
fi

# 7. Hourly heartbeat
if should_send_heartbeat; then
  send_heartbeat
fi

# 8. Daily summary
if should_send_daily_summary; then
  send_daily_summary
fi

# 9. Write status.json for NodePulse dashboard
write_status_json

log "========== DeNet Monitor Run Finished =========="
