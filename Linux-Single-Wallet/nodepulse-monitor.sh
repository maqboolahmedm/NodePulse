#!/bin/bash

# ============================================================
# NodePulse Monitor & Auto-Restart Script
# Linux Single-Wallet Version
# v3.3 — RC14 compatible | All fixes applied
# github.com/maqboolahmedm/NodePulse
#
# Fixes in this version:
#   - single instance lock
#   - DENODE_PASSWORD check at startup
#   - storage mount check before every restart
#   - tunnel check uses license-*.log first
#   - proof string updated to "Successfully submitted proof"
#   - context deadline exceeded removed from ERROR_PATTERNS
#   - penalty restart disabled (alert only)
#   - watchdog: restart loop detection
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

# Per-node RPC endpoints
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

# --- Paths ---
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
GUARD_DIR="$HOME/.nodepulse_guard"
PAUSED_FILE="$GUARD_DIR/paused_nodes"
LOCK_FILE="/tmp/nodepulse-monitor.lock"

# --- Config ---
PENALTY_WARN=5
PENALTY_CRITICAL=8
PENALTY_MAX=10
CYCLE_MINUTES=90
DISK_ALERT_THRESHOLD=85
DAILY_SUMMARY_HOUR=8
LOCAL_TIMEZONE="YOUR_TIMEZONE"
TUNNEL_SILENCE_THRESHOLD=6000

STORAGE_DRIVES=(
  "YOUR_STORAGE_PATH/YOUR_LICENSE_1"
  "YOUR_STORAGE_PATH/YOUR_LICENSE_2"
  "YOUR_STORAGE_PATH/YOUR_LICENSE_3"
  "YOUR_STORAGE_PATH/YOUR_LICENSE_4"
  "YOUR_STORAGE_PATH/YOUR_LICENSE_5"
  "YOUR_STORAGE_PATH/YOUR_LICENSE_6"
)

export DISPLAY=:0
export XAUTHORITY="$HOME/.Xauthority"
export DENODE_PASSWORD="YOUR_NODE_PASSWORD"

mkdir -p "$NODE_LOG_DIR" "$GUARD_DIR" "$(dirname $STATUS_JSON)" 2>/dev/null || true
touch "$PID_STATE_FILE" "$LAST_SEEN_FILE" "$DOWNTIME_LOG" "$PENALTY_FILE" "$PAUSED_FILE"

# ── Single instance lock ─────────────────────────────────────
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] Already running — skipping this run" >> "$LOG_FILE"
  exit 0
fi
trap "rm -f $LOCK_FILE" EXIT
# ─────────────────────────────────────────────────────────────

# ============================================================
# Time
# ============================================================
now_utc()  { date -u '+%Y-%m-%d %H:%M:%S UTC'; }
now_local(){ TZ="${LOCAL_TIMEZONE}" date '+%H:%M:%S %Z'; }

# ============================================================
# Core
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
    log "⚠️ Telegram: No response"
  fi
}

is_node_running() {
  ps aux | grep -v grep | grep "$DENODE_BIN" | grep -- "--license $1" > /dev/null 2>&1
}

get_node_pid() {
  ps aux | grep -v grep | grep "$DENODE_BIN" | grep -- "--license $1" | awk '{print $2}' | head -n 1
}

is_paused() {
  grep -qx "$1" "$PAUSED_FILE" 2>/dev/null
}

# ============================================================
# Storage mount check — must pass before any restart
# ============================================================
check_storage_mounted() {
  local LICENSE="$1"
  local DRIVE="${NODE_STORAGE[$LICENSE]}"
  if [ -z "$DRIVE" ]; then
    log "⚠️ No storage path configured for node $LICENSE"
    return 1
  fi
  if [ ! -d "$DRIVE" ]; then
    log "🔴 Storage not mounted for node $LICENSE: $DRIVE"
    send_telegram "🔴 <b>Storage Not Mounted</b>
🔑 License: <code>${LICENSE}</code>
💾 Path: <code>${DRIVE}</code>
⚠️ Node will NOT be restarted until storage is mounted
🕐 $(now_utc) | $(now_local)
📍 Host: $(hostname)"
    return 1
  fi
  if ! df "$DRIVE" > /dev/null 2>&1; then
    log "🔴 Storage not accessible for node $LICENSE: $DRIVE"
    return 1
  fi
  return 0
}

# ============================================================
# Tunnel Health Check
# Uses license-*.log (RC14 native) — not node-*.log (startup only)
# ============================================================
check_tunnel_health() {
  local LICENSE="$1"
  local PORT="${NODE_PORT[$LICENSE]}"
  local LOG_A="$NODE_LOG_DIR/license-${LICENSE}.log"
  local LOG_B="$NODE_LOG_DIR/node-${LICENSE}.log"
  local LOG="${LOG_A}"; [ ! -f "$LOG" ] && LOG="$LOG_B"

  local PORT_OPEN=0 LOG_FRESH=0

  if [ -n "$PORT" ] && ss -tlnp 2>/dev/null | grep -q ":${PORT}"; then
    PORT_OPEN=1
  fi

  if [ -f "$LOG" ]; then
    local LOG_AGE=$(( $(date +%s) - $(stat -c %Y "$LOG" 2>/dev/null || echo 0) ))
    [ "$LOG_AGE" -lt "$TUNNEL_SILENCE_THRESHOLD" ] && LOG_FRESH=1
  fi

  if [ "$PORT_OPEN" -eq 0 ] && [ "$LOG_FRESH" -eq 0 ]; then echo "DEAD"
  elif [ "$PORT_OPEN" -eq 0 ]; then echo "NO_PORT"
  elif [ "$LOG_FRESH" -eq 0 ]; then echo "SILENT"
  else echo "OK"
  fi
}

get_node_uptime() {
  local LICENSE="$1"
  local PID; PID=$(get_node_pid "$LICENSE")
  if [ -z "$PID" ]; then echo "not running"; return; fi
  local ETIME; ETIME=$(ps -o etime= -p "$PID" 2>/dev/null | tr -d ' ')
  if [ -z "$ETIME" ]; then echo "unknown"; return; fi
  local DAYS=0 HOURS=0 MINS=0
  if echo "$ETIME" | grep -q '-'; then
    DAYS=$(echo "$ETIME" | cut -d'-' -f1); ETIME=$(echo "$ETIME" | cut -d'-' -f2)
  fi
  local PARTS; IFS=':' read -ra PARTS <<< "$ETIME"
  case ${#PARTS[@]} in
    3) HOURS=${PARTS[0]}; MINS=${PARTS[1]} ;;
    2) MINS=${PARTS[0]} ;;
  esac
  DAYS=$((10#$DAYS)); HOURS=$((10#$HOURS)); MINS=$((10#$MINS))
  local R=""
  [ "$DAYS"  -gt 0 ] && R="${DAYS}d "
  [ "$HOURS" -gt 0 ] && R="${R}${HOURS}h "
  [ "$MINS"  -gt 0 ] && R="${R}${MINS}m"
  [ -z "$R" ] && R="< 1m"
  echo "$R"
}

# ============================================================
# Restart — storage check + password check before proceeding
# ============================================================
restart_node() {
  local LICENSE="$1"

  # Storage must be mounted
  if ! check_storage_mounted "$LICENSE"; then
    log "❌ Restart aborted for $LICENSE — storage not mounted"
    return 1
  fi

  # Password must be set
  if [ -z "$DENODE_PASSWORD" ]; then
    log "❌ Restart aborted for $LICENSE — DENODE_PASSWORD not set"
    send_telegram "🔴 <b>Restart Aborted — Password Missing</b>
🔑 License: <code>${LICENSE}</code>
⚠️ DENODE_PASSWORD is not set
💡 Run: export DENODE_PASSWORD=your_password
🕐 $(now_utc) | $(now_local)"
    return 1
  fi

  local OLD_PID; OLD_PID=$(get_node_pid "$LICENSE")
  [ -z "$OLD_PID" ] && OLD_PID=$(get_saved_pid "$LICENSE")

  local LAST_SEEN OFFLINE_DURATION WENT_DOWN_UTC
  LAST_SEEN=$(get_last_seen "$LICENSE")
  if [ -n "$LAST_SEEN" ]; then
    local NOW; NOW=$(date +%s)
    OFFLINE_DURATION=$(format_duration $(( NOW - LAST_SEEN )))
    WENT_DOWN_UTC=$(date -u -d "@${LAST_SEEN}" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || \
                    date -u -r "$LAST_SEEN" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null)
  else
    OFFLINE_DURATION="unknown"; WENT_DOWN_UTC="unknown"
  fi

  log "Restarting node $LICENSE (offline ~${OFFLINE_DURATION})..."

  nohup "$DENODE_BIN" \
    --address "$WALLET_ADDRESS" \
    --license "$LICENSE" \
    >> "$NODE_LOG_DIR/node-${LICENSE}.log" 2>&1 &

  sleep 3

  if is_node_running "$LICENSE"; then
    local NEW_PID; NEW_PID=$(get_node_pid "$LICENSE")
    increment_restart_count "$LICENSE"
    local TOTAL; TOTAL=$(get_restart_count "$LICENSE")
    save_pid "$LICENSE" "$NEW_PID"
    update_last_seen "$LICENSE"
    echo "${LICENSE}|$(date -u '+%Y-%m-%d %H:%M:%S UTC')|${WENT_DOWN_UTC}|${OFFLINE_DURATION}|${OLD_PID:-unknown}|${NEW_PID}" >> "$DOWNTIME_LOG"
    log "✅ Node $LICENSE restarted (PID: $NEW_PID, offline ~${OFFLINE_DURATION}, Total: $TOTAL)"
    send_telegram "✅ <b>DeNet Node Restarted</b>
🔑 License: <code>${LICENSE}</code>
🆔 Old PID: <code>${OLD_PID:-unknown}</code> → New: <code>${NEW_PID}</code>
🔄 Total Restarts: <b>${TOTAL}</b>
⏱ Offline: <b>${OFFLINE_DURATION}</b>
🕐 $(now_utc) | $(now_local)
📍 Host: $(hostname)"
  else
    log "❌ Node $LICENSE FAILED to restart!"
    send_telegram "❌ <b>DeNet Node FAILED to Restart</b>
🔑 License: <code>${LICENSE}</code>
⚠️ Manual intervention required!
⏱ Was offline: <b>${OFFLINE_DURATION}</b>
🕐 $(now_utc) | $(now_local)
📍 Host: $(hostname)"
  fi
}

# ============================================================
# Restart Counter
# ============================================================
increment_restart_count() {
  local LICENSE="$1"
  local CURRENT; CURRENT=$(get_restart_count "$LICENSE")
  local NEW=$(( CURRENT + 1 ))
  sed -i "/^${LICENSE}=/d" "$RESTART_COUNT_FILE" 2>/dev/null
  echo "${LICENSE}=${NEW}" >> "$RESTART_COUNT_FILE"
}

get_restart_count() {
  [ ! -f "$RESTART_COUNT_FILE" ] && echo "0" && return
  local C; C=$(grep "^${1}=" "$RESTART_COUNT_FILE" 2>/dev/null | cut -d= -f2)
  echo "${C:-0}"
}

get_all_restart_counts() {
  local LINES=""
  for LIC in "${LICENSES[@]}"; do
    local C; C=$(get_restart_count "$LIC")
    local I="🟢"; [ "$C" -gt 0 ] && I="🔄"; [ "$C" -ge 5 ] && I="🔴"
    LINES="${LINES}${I} Node <code>${LIC}</code> — restarted <b>${C}</b> time(s)\n"
  done
  echo -e "$LINES"
}

# ============================================================
# PID Tracking
# ============================================================
get_saved_pid()    { local V; V=$(grep "^${1}=" "$PID_STATE_FILE" 2>/dev/null | cut -d= -f2); echo "${V:-}"; }
save_pid()         { sed -i "/^${1}=/d" "$PID_STATE_FILE" 2>/dev/null; echo "${1}=${2}" >> "$PID_STATE_FILE"; }
update_last_seen() { local N; N=$(date +%s); sed -i "/^${1}=/d" "$LAST_SEEN_FILE" 2>/dev/null; echo "${1}=${N}" >> "$LAST_SEEN_FILE"; }
get_last_seen()    { local V; V=$(grep "^${1}=" "$LAST_SEEN_FILE" 2>/dev/null | cut -d= -f2); echo "${V:-}"; }

format_duration() {
  local SECS="$1"
  local D=$(( SECS/86400 )) H=$(( (SECS%86400)/3600 )) M=$(( (SECS%3600)/60 ))
  local R=""
  [ "$D" -gt 0 ] && R="${D}d "
  [ "$H" -gt 0 ] && R="${R}${H}h "
  R="${R}${M}m"; echo "$R"
}

record_downtime_event() {
  local LICENSE="$1" OLD_PID="$2" NEW_PID="$3"
  local LS; LS=$(get_last_seen "$LICENSE")
  local NOW; NOW=$(date +%s)
  local WD="unknown" DUR="unknown"
  if [ -n "$LS" ]; then
    WD=$(date -u -d "@${LS}" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || date -u -r "$LS" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null)
    DUR=$(format_duration $(( NOW - LS )))
  fi
  echo "${LICENSE}|$(date -u '+%Y-%m-%d %H:%M:%S UTC')|${WD}|${DUR}|${OLD_PID}|${NEW_PID}" >> "$DOWNTIME_LOG"
  echo "$WD|$DUR"
}

check_pid_change() {
  local LICENSE="$1"
  local CUR; CUR=$(get_node_pid "$LICENSE")
  local SAV; SAV=$(get_saved_pid "$LICENSE")
  if [ -n "$SAV" ] && [ -n "$CUR" ] && [ "$SAV" != "$CUR" ]; then
    local INFO; INFO=$(record_downtime_event "$LICENSE" "$SAV" "$CUR")
    echo "RESTARTED|${SAV}|${CUR}|$(echo "$INFO"|cut -d'|' -f1)|$(echo "$INFO"|cut -d'|' -f2)"
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
reset_penalty()     { set_penalty_count "$1" "0"; log "✅ Node $1 penalties reset to 0"; }

check_proof_status() {
  local LICENSE="$1"
  # FIX: check license-*.log first (RC14 native), fall back to node-*.log
  local LOG_A="$NODE_LOG_DIR/license-${LICENSE}.log"
  local LOG_B="$NODE_LOG_DIR/node-${LICENSE}.log"
  local NODE_LOG=""
  [ -f "$LOG_A" ] && NODE_LOG="$LOG_A" || { [ -f "$LOG_B" ] && NODE_LOG="$LOG_B"; }
  [ -z "$NODE_LOG" ] && echo "UNKNOWN" && return
  local RECENT; RECENT=$(tail -100 "$NODE_LOG" 2>/dev/null)
  # FIX: use proof string confirmed by DeNet team
  echo "$RECENT" | grep -qiE "Successfully submitted proof|Proof of Storage stage handling completed|Collect Proofs handling completed" && echo "PROOF_OK" && return
  echo "$RECENT" | grep -qiE "Failed to send hash proof|failed to submit Send Hash Proof" && echo "MISSED" && return
  echo "UNKNOWN"
}

check_and_update_penalties() {
  local LICENSE="$1"
  is_node_running "$LICENSE" || return
  local PROOF_STATUS; PROOF_STATUS=$(check_proof_status "$LICENSE")
  local CUR_PEN; CUR_PEN=$(get_penalty_count "$LICENSE")
  if [ "$PROOF_STATUS" = "PROOF_OK" ]; then
    if [ "$CUR_PEN" -gt 0 ]; then
      reset_penalty "$LICENSE"
      send_telegram "✅ <b>Node ${LICENSE} — Penalties Reset</b>
📊 Was: <b>${CUR_PEN}</b> → Now: <b>0</b>
✅ Proof submitted successfully
🕐 $(now_utc) | $(now_local)"
    fi
    return
  fi
  if [ "$PROOF_STATUS" = "MISSED" ]; then
    local NEW_PEN; NEW_PEN=$(increment_penalty "$LICENSE")
    log "⚠️ Node $LICENSE missed proof — penalties: ${NEW_PEN}/${PENALTY_MAX}"
    if [ "$NEW_PEN" -eq "$PENALTY_WARN" ]; then
      send_telegram "⚠️ <b>Node ${LICENSE} — Penalty Warning</b>
📊 Penalties: <b>${NEW_PEN}/${PENALTY_MAX}</b>
⏱ ~$(( (PENALTY_MAX - NEW_PEN) * CYCLE_MINUTES / 60 ))h before pool removal
🕐 $(now_utc) | $(now_local)"
    elif [ "$NEW_PEN" -ge "$PENALTY_CRITICAL" ] && [ "$NEW_PEN" -lt "$PENALTY_MAX" ]; then
      send_telegram "🚨 <b>Node ${LICENSE} — CRITICAL Penalty</b>
📊 Penalties: <b>${NEW_PEN}/${PENALTY_MAX}</b>
⚠️ Only $(( PENALTY_MAX - NEW_PEN )) cycle(s) left
🕐 $(now_utc) | $(now_local)"
    elif [ "$NEW_PEN" -ge "$PENALTY_MAX" ]; then
      # AUTO-RESTART DISABLED — actual pool removal takes 15h not 10 cycles
      send_telegram "🚫 <b>Node ${LICENSE} — Penalty Threshold Reached</b>
📊 Penalties: <b>${NEW_PEN}/${PENALTY_MAX}</b>
ℹ️ Actual pool removal takes 15h of inactivity — node will auto re-join
⚠️ Restart manually only if node is truly stuck
🕐 $(now_utc) | $(now_local)"
    fi
  fi
}

# ============================================================
# DuckDNS
# ============================================================
update_duckdns() {
  local R; R=$(curl -s --max-time 10 \
    "https://www.duckdns.org/update?domains=${DUCKDNS_DOMAIN}&token=${DUCKDNS_TOKEN}&ip=")
  [ "$R" = "OK" ] && log "🌐 DuckDNS updated." || log "⚠️ DuckDNS failed: $R"
}

# ============================================================
# Disk Monitoring
# ============================================================
check_disk_space() {
  for DRIVE in "${STORAGE_DRIVES[@]}"; do
    if [ ! -d "$DRIVE" ]; then
      log "⚠️ Drive $DRIVE not mounted!"
      send_telegram "⚠️ <b>Drive Not Mounted</b>
💾 Drive: <code>${DRIVE}</code>
🕐 $(now_utc) | $(now_local)
📍 Host: $(hostname)"
      continue
    fi
    local USAGE; USAGE=$(df "$DRIVE" | awk 'NR==2 {gsub("%",""); print $5}')
    local USED; USED=$(df -h "$DRIVE" | awk 'NR==2 {print $3}')
    local TOTAL; TOTAL=$(df -h "$DRIVE" | awk 'NR==2 {print $2}')
    local FREE; FREE=$(df -h "$DRIVE" | awk 'NR==2 {print $4}')
    log "💾 $DRIVE — ${USAGE}% (${USED}/${TOTAL}, free: ${FREE})"
    if [ "$USAGE" -ge "$DISK_ALERT_THRESHOLD" ]; then
      send_telegram "⚠️ <b>Disk Space Warning</b>
💾 Drive: <code>${DRIVE}</code>
📊 Usage: <b>${USAGE}%</b> — ${USED}/${TOTAL} (free: ${FREE})
🕐 $(now_utc) | $(now_local)"
    fi
  done
}

get_disk_summary() {
  local S=""
  for DRIVE in "${STORAGE_DRIVES[@]}"; do
    if [ ! -d "$DRIVE" ]; then S="${S}❌ $(basename $DRIVE) — NOT MOUNTED\n"; continue; fi
    local U; U=$(df "$DRIVE" | awk 'NR==2 {gsub("%",""); print $5}')
    local UD; UD=$(df -h "$DRIVE" | awk 'NR==2 {print $3}')
    local T; T=$(df -h "$DRIVE" | awk 'NR==2 {print $2}')
    local F; F=$(df -h "$DRIVE" | awk 'NR==2 {print $4}')
    local I="🟢"; [ "$U" -ge "$DISK_ALERT_THRESHOLD" ] && I="🔴"
    S="${S}${I} $(basename $DRIVE): ${U}% — ${UD}/${T} (free: ${F})\n"
  done
  echo -e "$S"
}

# ============================================================
# Error Alerts
# NOTE: "context deadline exceeded" removed — RC14 P2P noise
# ============================================================
ERROR_PATTERNS=(
  "roothash mismatch|Roothash Mismatch"
  "failed to unlock account|Password/Unlock Error"
  "already known|Duplicate Transaction"
  "i/o timeout|Network I/O Timeout"
)

check_node_errors() {
  local LICENSE="$1"
  local LOG_A="$NODE_LOG_DIR/license-${LICENSE}.log"
  local LOG_B="$NODE_LOG_DIR/node-${LICENSE}.log"
  local NODE_LOG=""
  [ -f "$LOG_A" ] && NODE_LOG="$LOG_A" || { [ -f "$LOG_B" ] && NODE_LOG="$LOG_B"; }
  [ -z "$NODE_LOG" ] && return
  local RECENT; RECENT=$(tail -50 "$NODE_LOG" 2>/dev/null)
  for PATTERN_ENTRY in "${ERROR_PATTERNS[@]}"; do
    local PATTERN="${PATTERN_ENTRY%%|*}" LABEL="${PATTERN_ENTRY##*|}"
    if echo "$RECENT" | grep -qi "$PATTERN"; then
      local KEY="${LICENSE}_${PATTERN// /_}"
      local LAST=""; [ -f "$ERROR_STATE_FILE" ] && LAST=$(grep "^${KEY}=" "$ERROR_STATE_FILE" 2>/dev/null | cut -d= -f2)
      local NOW; NOW=$(date +%s)
      if [ -z "$LAST" ] || [ $(( NOW - LAST )) -ge 3600 ]; then
        local LINE; LINE=$(echo "$RECENT" | grep -i "$PATTERN" | tail -1)
        log "⚠️ Node $LICENSE — $LABEL"
        send_telegram "⚠️ <b>Node Error Detected</b>
🔑 License: <code>${LICENSE}</code>
🔴 Error: <b>${LABEL}</b>
📋 <code>${LINE}</code>
🕐 $(now_utc) | $(now_local)"
        sed -i "/^${KEY}=/d" "$ERROR_STATE_FILE" 2>/dev/null
        echo "${KEY}=${NOW}" >> "$ERROR_STATE_FILE"
      fi
    fi
  done
}

# ============================================================
# Watchdog — restart loop detection
# ============================================================
watchdog_check() {
  local NOW=$(date +%s)
  for LICENSE in "${LICENSES[@]}"; do
    local COUNT; COUNT=$(get_restart_count "$LICENSE")
    [ "$COUNT" -lt 3 ] && continue
    local LAST_ENTRY; LAST_ENTRY=$(grep "^${LICENSE}|" "$DOWNTIME_LOG" 2>/dev/null | tail -1)
    [ -z "$LAST_ENTRY" ] && continue
    local LAST_TS; LAST_TS=$(echo "$LAST_ENTRY" | cut -d'|' -f2)
    local LAST_EPOCH; LAST_EPOCH=$(date -d "$LAST_TS" +%s 2>/dev/null || echo 0)
    if [ $(( NOW - LAST_EPOCH )) -lt 1800 ]; then
      if ! is_paused "$LICENSE"; then
        log "🔁 Restart loop detected for $LICENSE — auto-pausing"
        echo "$LICENSE" >> "$PAUSED_FILE"
        send_telegram "🔁 <b>Restart Loop Detected — Node Paused</b>
🔑 License: <code>${LICENSE}</code>
🔄 ${COUNT} restarts in last 30 min
🛑 Node auto-paused — investigate and use /start ${LICENSE} to resume
🕐 $(now_utc) | $(now_local)
📍 Host: $(hostname)"
      fi
    fi
  done
}

# ============================================================
# Heartbeat
# ============================================================
send_heartbeat() {
  local STATUS_LINES="" RESTART_ALERT="" HAS_ALERT=0
  for LICENSE in "${LICENSES[@]}"; do
    if is_node_running "$LICENSE"; then
      local PID; PID=$(get_node_pid "$LICENSE")
      local UP; UP=$(get_node_uptime "$LICENSE")
      local RC; RC=$(get_restart_count "$LICENSE")
      local PC; PC=$(check_pid_change "$LICENSE")
      local PT; PT=$(get_penalty_count "$LICENSE")
      local PI="🟢"; [ "$PT" -ge "$PENALTY_WARN" ] && PI="🟡"; [ "$PT" -ge "$PENALTY_CRITICAL" ] && PI="🟠"
      local PAUSE_TAG=""; is_paused "$LICENSE" && PAUSE_TAG=" 🛑PAUSED"
      if [ "$PC" != "OK" ]; then
        local OLD WD DUR
        OLD=$(echo "$PC"|cut -d'|' -f2); WD=$(echo "$PC"|cut -d'|' -f4); DUR=$(echo "$PC"|cut -d'|' -f5)
        STATUS_LINES="${STATUS_LINES}⚠️ <code>${LICENSE}</code> — PID <code>${PID}</code> — Up: <b>${UP}</b> — R: <b>${RC}</b> — ${PI} P: <b>${PT}/${PENALTY_MAX}</b>${PAUSE_TAG}\n"
        RESTART_ALERT="${RESTART_ALERT}⚠️ <code>${LICENSE}</code> restarted silently!\n"
        RESTART_ALERT="${RESTART_ALERT}   🔴 Old PID: <code>${OLD}</code> → 🟢 New: <code>${PID}</code>\n"
        RESTART_ALERT="${RESTART_ALERT}   📅 Last alive: <b>${WD}</b> | ⏱ Offline: <b>${DUR}</b>\n"
        HAS_ALERT=1
      else
        STATUS_LINES="${STATUS_LINES}🟢 <code>${LICENSE}</code> — PID <code>${PID}</code> — Up: <b>${UP}</b> — R: <b>${RC}</b> — ${PI} P: <b>${PT}/${PENALTY_MAX}</b>${PAUSE_TAG}\n"
      fi
      save_pid "$LICENSE" "$PID"; update_last_seen "$LICENSE"
    else
      local RC; RC=$(get_restart_count "$LICENSE")
      local PAUSE_TAG=""; is_paused "$LICENSE" && PAUSE_TAG=" 🛑PAUSED"
      STATUS_LINES="${STATUS_LINES}🔴 <code>${LICENSE}</code> — <b>DOWN</b> — R: <b>${RC}</b>${PAUSE_TAG}\n"
    fi
  done
  local ALERT_BLOCK=""
  [ "$HAS_ALERT" -eq 1 ] && ALERT_BLOCK="
⚠️ <b>Silent Restarts:</b>
$(echo -e "$RESTART_ALERT")"
  send_telegram "💓 <b>NodePulse HeartBeat</b>
📍 Host: $(hostname)
🕐 $(now_utc) | $(now_local)
${ALERT_BLOCK}
<b>Node Status:</b>
$(echo -e "$STATUS_LINES")
💾 <b>Disk:</b>
$(get_disk_summary)"
  log "💓 Heartbeat sent."
  date +%s > "$HEARTBEAT_FILE"
}

should_send_heartbeat() {
  [ ! -f "$HEARTBEAT_FILE" ] && return 0
  local DIFF=$(( $(date +%s) - $(cat "$HEARTBEAT_FILE") ))
  [ "$DIFF" -ge 3600 ] && return 0; return 1
}

# ============================================================
# Daily Summary
# ============================================================
send_daily_summary() {
  local LINES="" UP=0 DOWN=0
  for LICENSE in "${LICENSES[@]}"; do
    if is_node_running "$LICENSE"; then
      LINES="${LINES}🟢 <code>${LICENSE}</code> — Up: <b>$(get_node_uptime $LICENSE)</b>\n"
      UP=$(( UP + 1 ))
    else
      LINES="${LINES}🔴 <code>${LICENSE}</code> — DOWN\n"
      DOWN=$(( DOWN + 1 ))
    fi
  done
  local OVERALL="✅ All nodes healthy"
  [ "$DOWN" -gt 0 ] && OVERALL="⚠️ ${DOWN} node(s) DOWN"
  send_telegram "📊 <b>DeNet Daily Summary</b>
📅 $(now_utc) | $(now_local)
📍 Host: $(hostname)

<b>Nodes (${UP}/${#LICENSES[@]} online):</b>
$(echo -e "$LINES")
<b>Overall:</b> ${OVERALL}
💾 <b>Disk:</b>
$(get_disk_summary)
🔄 <b>Restarts:</b>
$(get_all_restart_counts)"
  date +%s > "$DAILY_SUMMARY_FILE"
  log "📊 Daily summary sent."
}

should_send_daily_summary() {
  local H=$((10#$(TZ="${LOCAL_TIMEZONE}" date '+%H')))
  [ "$H" -ne "$DAILY_SUMMARY_HOUR" ] && return 1
  [ ! -f "$DAILY_SUMMARY_FILE" ] && return 0
  local DIFF=$(( $(date +%s) - $(cat "$DAILY_SUMMARY_FILE") ))
  [ "$DIFF" -lt 82800 ] && return 1; return 0
}

# ============================================================
# Chain Status
# ============================================================
check_chain_status_from_logs() {
  log "⛓ Checking on-chain status from node logs..."
  python3 - <<CHAINEOF
import os, re, json
from datetime import datetime, timezone, timedelta

licenses = [$(printf '"%s",' "${LICENSES[@]}" | sed 's/,$//')]
log_dir  = os.path.expanduser("$NODE_LOG_DIR")
now_utc  = datetime.now(timezone.utc)
results  = {}

PROOF_OK   = re.compile(r'Successfully submitted proof|Proof of Storage stage handling completed|Collect Proofs handling completed', re.IGNORECASE)
PROOF_FAIL = re.compile(r'Failed to send hash proof|failed to submit Send Hash Proof', re.IGNORECASE)
STAGE      = re.compile(r'Current Stage:\s*(\w[\w ]+\w)', re.IGNORECASE)
POOL       = re.compile(r'License ID is in (\d+) pool', re.IGNORECASE)
TS         = re.compile(r'(\d{2}-\d{2} \d{2}:\d{2}:\d{2})')
IST        = timedelta(hours=5, minutes=30)

def parse_ts(line):
    m = TS.search(re.sub(r'\x1b\[[0-9;]*m','',line))
    if not m: return None
    try:
        dt = datetime.strptime(f"{datetime.now().year}-{m.group(1)}", "%Y-%m-%d %H:%M:%S")
        return (dt - IST).replace(tzinfo=timezone.utc)
    except: return None

for lic in licenses:
    log_a = os.path.join(log_dir, f"license-{lic}.log")
    log_b = os.path.join(log_dir, f"node-{lic}.log")
    log_file = log_a if os.path.exists(log_a) else (log_b if os.path.exists(log_b) else None)
    if not log_file:
        results[str(lic)] = {"status":"unknown","age":"unknown","pool":"","stage":"","last_error":""}
        continue
    try:
        with open(log_file,'rb') as f:
            f.seek(0,2); f.seek(max(0,f.tell()-102400))
            lines = f.read().decode('utf-8',errors='ignore').splitlines()
    except Exception as e:
        results[str(lic)] = {"status":"unknown","age":str(e),"pool":"","stage":"","last_error":""}
        continue
    last_proof=None; pool=""; stage=""; last_err=""; last_ts=None
    for line in reversed(lines):
        clean = re.sub(r'\x1b\[[0-9;]*m','',line)
        ts = parse_ts(clean)
        if ts and last_ts is None: last_ts = ts
        if not pool:
            m=POOL.search(clean)
            if m: pool=m.group(1)
        if not stage:
            m=STAGE.search(clean)
            if m: stage=m.group(1).strip()
        if last_proof is None and PROOF_OK.search(clean):
            last_proof = ts or last_ts
        if not last_err and PROOF_FAIL.search(clean):
            last_err = clean.strip()[:100]
        if last_proof and pool and stage: break
    if last_proof:
        age_min = (now_utc - last_proof).total_seconds()/60
        status = "online" if age_min<95 else ("pending" if age_min<190 else "offline")
        age_str = f"{int(age_min)}m ago" if age_min<60 else f"{age_min/60:.1f}h ago"
    else:
        status="unknown"; age_str="unknown"
    results[str(lic)] = {"status":status,"age":age_str,"pool":pool,"stage":stage,"last_error":last_err}
    print(f"[{lic}] {status.upper()} | Pool:{pool} | Stage:{stage} | Last proof:{age_str}")

out = {"fetched_at":now_utc.strftime("%Y-%m-%d %H:%M:%S UTC"),"source":"node_logs","nodes":results}
with open(os.path.expanduser("$CHAIN_STATUS_FILE"),'w') as f:
    json.dump(out,f,indent=2)
print("Chain status saved ✅")
CHAINEOF
  log "⛓ Chain status updated."
}

should_check_chain_status() {
  [ ! -f "$CHAIN_STATUS_FILE" ] && return 0
  local LAST; LAST=$(python3 -c "
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
  [ $(( $(date +%s) - LAST )) -ge 300 ] && return 0; return 1
}

# ============================================================
# Write status.json
# ============================================================
write_status_json() {
  local VER; VER=$("$DENODE_BIN" --version 2>/dev/null | head -1 || echo "unknown")
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
guard_dir   = os.path.expanduser("~/.nodepulse_guard")
paused_file = os.path.expanduser("$PAUSED_FILE")

def read_kv(path):
    out={}
    try:
        for line in open(path):
            if "=" in line:
                k,v=line.strip().split("=",1); out[k]=v
    except: pass
    return out

saved_pids  = read_kv(pid_file)
last_seen   = read_kv(seen_file)
restart_cnt = read_kv(rc_file)
penalties   = read_kv(pen_file)
try: paused_set = set(open(paused_file).read().splitlines())
except: paused_set = set()

def get_score(lic):
    try:
        with open(os.path.join(guard_dir,"score_"+str(lic))) as f:
            return max(0,min(100,int(f.read().strip())))
    except: return None

def get_tunnel(lic):
    try:
        with open(os.path.join(guard_dir,"tunnel_"+str(lic))) as f:
            return f.read().strip()
    except: return None

def get_last_downtime(lic):
    try:
        lines=[l for l in open(dt_log) if l.startswith(str(lic)+"|")]
        if not lines: return None
        p=lines[-1].strip().split("|")
        return {"restarted_at":p[1],"last_alive":p[2],"offline_duration":p[3],"old_pid":p[4],"new_pid":p[5]}
    except: return None

def get_ps_info(lic):
    try:
        r=subprocess.run(["ps","aux"],capture_output=True,text=True)
        for line in r.stdout.splitlines():
            if "/usr/bin/denode" in line and f"--license {lic}" in line and "grep" not in line:
                p=line.split(); pid=p[1]
                r2=subprocess.run(["ps","-o","etime=","-p",pid],capture_output=True,text=True)
                return pid,r2.stdout.strip()
    except: pass
    return None,None

def parse_etime(et):
    if not et: return "unknown"
    d,h,m=0,0,0
    if "-" in et: d,et=et.split("-",1); d=int(d)
    p=et.split(":")
    if len(p)==3: h,m=int(p[0]),int(p[1])
    elif len(p)==2: m=int(p[0])
    r=""
    if d: r+=f"{d}d "
    if h: r+=f"{h}h "
    r+=f"{m}m"
    return r.strip() or "< 1m"

def get_disk(drive):
    try:
        r=subprocess.run(["df","-h",drive],capture_output=True,text=True)
        p=r.stdout.splitlines()[1].split()
        return {"used":p[2],"total":p[1],"free":p[3],"pct":int(p[4].replace("%",""))}
    except: return None

now_ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
storage = {$(for L in "${LICENSES[@]}"; do echo "\"${L}\":\"${NODE_STORAGE[$L]}\","; done)}

nodes=[]
for lic in licenses:
    pid,etime=get_ps_info(lic)
    running=pid is not None
    saved=saved_pids.get(str(lic),"")
    ls_ts=last_seen.get(str(lic),"")
    last_seen_str=""
    if ls_ts:
        try:
            dt=datetime.fromtimestamp(int(ls_ts),tz=timezone.utc)
            last_seen_str=dt.strftime("%Y-%m-%d %H:%M:%S UTC")
        except: pass
    nodes.append({
        "license":lic,"status":"running" if running else "down",
        "paused":str(lic) in paused_set,"pid":pid or "",
        "uptime":parse_etime(etime) if running else "",
        "restarts":int(restart_cnt.get(str(lic),0)),
        "penalties":int(penalties.get(str(lic),0)),"penalty_max":penalty_max,
        "pid_changed":bool(saved and pid and saved!=pid),
        "old_pid":saved if (saved and pid and saved!=pid) else "",
        "last_seen":last_seen_str,"last_downtime":get_last_downtime(lic),
        "disk":get_disk(storage.get(str(lic),"")),
        "score":get_score(lic),"tunnel":get_tunnel(lic),
    })

data={"app":"NodePulse","version":"${VER}","host":"$(hostname)","updated":now_ts,"nodes":nodes,
      "chain_status":json.load(open(os.path.expanduser("$CHAIN_STATUS_FILE"))) if os.path.exists(os.path.expanduser("$CHAIN_STATUS_FILE")) else None}
out="$STATUS_JSON"
os.makedirs(os.path.dirname(out),exist_ok=True)
with open(out,"w") as f: json.dump(data,f,indent=2)
print(f"status.json written → {out}")
PYEOF
  log "📡 status.json updated."
}

# ============================================================
# Main Monitor Loop
# ============================================================
log "========== NodePulse Monitor Started (SW v3.3) =========="

# ── Password check ───────────────────────────────────────────
if [ -z "$DENODE_PASSWORD" ]; then
  log "🔴 DENODE_PASSWORD not set — nodes cannot be restarted"
  send_telegram "🔴 <b>NodePulse Warning</b>
⚠️ DENODE_PASSWORD is not set
Nodes cannot be auto-restarted after this point
💡 Add to ~/.bashrc: export DENODE_PASSWORD=your_password
🕐 $(now_utc) | $(now_local)"
fi
# ─────────────────────────────────────────────────────────────

DOWN_COUNT=0

update_duckdns

for LICENSE in "${LICENSES[@]}"; do
  if is_paused "$LICENSE"; then
    log "⏸️  Node $LICENSE is PAUSED — skipping"
    continue
  fi

  if is_node_running "$LICENSE"; then
    PID=$(get_node_pid "$LICENSE")
    UPTIME=$(get_node_uptime "$LICENSE")
    log "✅ Node $LICENSE running (PID: $PID, Up: $UPTIME)"
    save_pid "$LICENSE" "$PID"
    update_last_seen "$LICENSE"

    # Tunnel health check
    TUNNEL=$(check_tunnel_health "$LICENSE")
    echo "$TUNNEL" > "$GUARD_DIR/tunnel_${LICENSE}"
    case "$TUNNEL" in
      DEAD)
        log "🔌 Node $LICENSE — tunnel DEAD (port closed + log silent)"
        send_telegram "🔌 <b>Node ${LICENSE} — Tunnel Dead</b>
⚠️ Port closed and log silent
🔄 Restarting to re-establish tunnel...
🕐 $(now_utc) | $(now_local)"
        OLD_PID=$(get_node_pid "$LICENSE")
        [ -n "$OLD_PID" ] && kill "$OLD_PID" 2>/dev/null && sleep 2
        restart_node "$LICENSE"
        ;;
      NO_PORT) log "🔌 Node $LICENSE — port not listening (log active)" ;;
      SILENT)  log "⚠️ Node $LICENSE — log silent (port open — monitoring)" ;;
      OK)      log "🔗 Node $LICENSE — tunnel OK" ;;
    esac
  else
    log "⚠️  Node $LICENSE DOWN — attempting restart..."
    DOWN_COUNT=$(( DOWN_COUNT + 1 ))
    send_telegram "⚠️ <b>Node Down</b>
🔑 License: <code>${LICENSE}</code>
🔄 Attempting restart...
🕐 $(now_utc) | $(now_local)"
    restart_node "$LICENSE"
  fi
done

[ "$DOWN_COUNT" -eq 0 ] && log "All nodes running normally." || log "$DOWN_COUNT node(s) restarted."

check_disk_space

for LICENSE in "${LICENSES[@]}"; do
  is_paused "$LICENSE" && continue
  check_node_errors "$LICENSE"
done

for LICENSE in "${LICENSES[@]}"; do
  is_paused "$LICENSE" && continue
  check_and_update_penalties "$LICENSE"
  log "📊 Node $LICENSE — penalties: $(get_penalty_count $LICENSE)/${PENALTY_MAX}"
done

watchdog_check

should_check_chain_status && check_chain_status_from_logs
should_send_heartbeat     && send_heartbeat
should_send_daily_summary && send_daily_summary
write_status_json

log "========== NodePulse Monitor Finished =========="
