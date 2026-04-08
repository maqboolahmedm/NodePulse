#!/bin/bash

# ============================================================
# DeNet Node Monitor & Auto-Restart Script — macOS
# NodePulse v2.0
# Template: Replace YOUR_XXX_HERE with your actual values
# Runs via launchd (macOS equivalent of cron/systemd)
# ============================================================

# --- Telegram Config ---
TELEGRAM_BOT_TOKEN="YOUR_TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="YOUR_TELEGRAM_CHAT_ID"

# --- Node Config ---
DENODE_BIN="/usr/local/bin/denode"
WALLET_ADDRESS="YOUR_WALLET_ADDRESS"
LICENSES=(YOUR_LICENSE_1 YOUR_LICENSE_2)  # e.g. (1072 1864 1865)
export DENODE_PASSWORD="YOUR_NODE_PASSWORD"

# --- Timezone Config ---
# Your local timezone e.g. "Asia/Kolkata", "Europe/Berlin", "America/New_York"
LOCAL_TIMEZONE="YOUR_TIMEZONE"

# --- Paths ---
LOG_FILE="$HOME/.denode/monitor.log"
NODE_LOG_DIR="$HOME/.denode/logs"
HEARTBEAT_FILE="$HOME/.denode/.last_heartbeat"
RESTART_COUNT_FILE="$HOME/.denode/.restart_counts"
PENALTY_FILE="$HOME/.denode/.node_penalties"
PID_STATE_FILE="$HOME/.denode/.node_pids"
LAST_SEEN_FILE="$HOME/.denode/.node_last_seen"
DOWNTIME_LOG="$HOME/.denode/.node_downtime_log"

# --- Penalty Config ---
PENALTY_WARN=5
PENALTY_CRITICAL=8
PENALTY_MAX=10

mkdir -p "$NODE_LOG_DIR"
touch "$RESTART_COUNT_FILE" "$PENALTY_FILE" "$PID_STATE_FILE" "$LAST_SEEN_FILE" "$DOWNTIME_LOG"

# ============================================================
# Time Functions
# ============================================================

now_utc()   { date -u '+%Y-%m-%d %H:%M:%S UTC'; }
now_local() { TZ="${LOCAL_TIMEZONE}" date '+%H:%M:%S %Z'; }

log() { echo "[$(now_utc) | $(now_local)] $1" | tee -a "$LOG_FILE"; }

send_telegram() {
  curl -s --max-time 15 -X POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    -d text="$1" \
    -d parse_mode="HTML" > /dev/null 2>&1
}

# ============================================================
# Node Helpers
# ============================================================

is_node_running() {
  ps aux | grep -v grep | grep "$DENODE_BIN" | grep -- "--license $1" > /dev/null 2>&1
}

get_node_pid() {
  ps aux | grep -v grep | grep "$DENODE_BIN" | grep -- "--license $1" | awk '{print $2}' | head -n 1
}

get_node_uptime() {
  local PID=$(get_node_pid "$1")
  [ -z "$PID" ] && echo "not running" && return
  local START
  START=$(ps -o lstart= -p "$PID" 2>/dev/null)
  if [ -z "$START" ]; then echo "unknown"; return; fi
  local START_SEC NOW_SEC DIFF
  START_SEC=$(date -j -f "%a %b %d %T %Y" "$START" "+%s" 2>/dev/null || date -d "$START" "+%s" 2>/dev/null)
  NOW_SEC=$(date "+%s")
  DIFF=$(( NOW_SEC - START_SEC ))
  local DAYS=$(( DIFF / 86400 )); local HOURS=$(( (DIFF % 86400) / 3600 )); local MINS=$(( (DIFF % 3600) / 60 ))
  local RESULT=""
  [ "$DAYS"  -gt 0 ] && RESULT="${DAYS}d "
  [ "$HOURS" -gt 0 ] && RESULT="${RESULT}${HOURS}h "
  [ "$MINS"  -gt 0 ] && RESULT="${RESULT}${MINS}m"
  [ -z "$RESULT"   ] && RESULT="< 1m"
  echo "$RESULT"
}

# ============================================================
# PID Tracking
# ============================================================

get_saved_pid() {
  local VAL=$(grep "^${1}=" "$PID_STATE_FILE" 2>/dev/null | cut -d= -f2)
  echo "${VAL:-}"
}

save_pid() {
  sed -i '' "/^${1}=/d" "$PID_STATE_FILE" 2>/dev/null
  echo "${1}=${2}" >> "$PID_STATE_FILE"
}

update_last_seen() {
  local NOW=$(date "+%s")
  sed -i '' "/^${1}=/d" "$LAST_SEEN_FILE" 2>/dev/null
  echo "${1}=${NOW}" >> "$LAST_SEEN_FILE"
}

get_last_seen() {
  local VAL=$(grep "^${1}=" "$LAST_SEEN_FILE" 2>/dev/null | cut -d= -f2)
  echo "${VAL:-}"
}

format_duration() {
  local SECS="$1"
  local DAYS=$(( SECS / 86400 )); local HOURS=$(( (SECS % 86400) / 3600 )); local MINS=$(( (SECS % 3600) / 60 ))
  local RESULT=""
  [ "$DAYS"  -gt 0 ] && RESULT="${DAYS}d "
  [ "$HOURS" -gt 0 ] && RESULT="${RESULT}${HOURS}h "
  RESULT="${RESULT}${MINS}m"
  echo "$RESULT"
}

# ============================================================
# Restart & Penalty Counter
# ============================================================

get_restart_count() {
  local COUNT=$(grep "^${1}=" "$RESTART_COUNT_FILE" 2>/dev/null | cut -d= -f2)
  echo "${COUNT:-0}"
}

increment_restart_count() {
  local NEW=$(( $(get_restart_count "$1") + 1 ))
  sed -i '' "/^${1}=/d" "$RESTART_COUNT_FILE" 2>/dev/null
  echo "${1}=${NEW}" >> "$RESTART_COUNT_FILE"
}

get_penalty_count() {
  local VAL=$(grep "^${1}=" "$PENALTY_FILE" 2>/dev/null | cut -d= -f2)
  echo "${VAL:-0}"
}

# ============================================================
# Restart Node
# ============================================================

restart_node() {
  local LICENSE="$1"

  # Get old PID — live process first, then saved file
  local OLD_PID
  OLD_PID=$(get_node_pid "$LICENSE")
  [ -z "$OLD_PID" ] && OLD_PID=$(get_saved_pid "$LICENSE")

  # Calculate downtime
  local LAST_SEEN OFFLINE_DURATION WENT_DOWN_UTC
  LAST_SEEN=$(get_last_seen "$LICENSE")
  if [ -n "$LAST_SEEN" ]; then
    local NOW=$(date +%s)
    local OFFLINE_SECS=$(( NOW - LAST_SEEN ))
    OFFLINE_DURATION=$(format_duration "$OFFLINE_SECS")
    WENT_DOWN_UTC=$(date -u -r "$LAST_SEEN" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || echo "unknown")
  else
    OFFLINE_DURATION="unknown"; WENT_DOWN_UTC="unknown"
  fi

  log "Restarting node $LICENSE (last alive: ${WENT_DOWN_UTC}, offline ~${OFFLINE_DURATION})..."
  nohup "$DENODE_BIN" --address "$WALLET_ADDRESS" --license "$LICENSE" \
    >> "$NODE_LOG_DIR/node-${LICENSE}.log" 2>&1 &
  sleep 3

  if is_node_running "$LICENSE"; then
    local NEW_PID=$(get_node_pid "$LICENSE")
    increment_restart_count "$LICENSE"
    save_pid "$LICENSE" "$NEW_PID"
    update_last_seen "$LICENSE"
    local TOTAL=$(get_restart_count "$LICENSE")
    echo "${LICENSE}|$(now_utc)|${WENT_DOWN_UTC}|${OFFLINE_DURATION}|${OLD_PID:-unknown}|${NEW_PID}" >> "$DOWNTIME_LOG"
    log "✅ Node $LICENSE restarted (PID: $NEW_PID, offline ~${OFFLINE_DURATION}, Total: $TOTAL)"
    send_telegram "✅ <b>DeNet Node Restarted</b>
🔑 License: <code>${LICENSE}</code>
🆔 Old PID: <code>${OLD_PID:-unknown}</code> → New: <code>${NEW_PID}</code>
🔄 Total Restarts: <b>${TOTAL}</b>
📅 Last alive: <b>${WENT_DOWN_UTC}</b>
⏱ Offline for: <b>${OFFLINE_DURATION}</b>
🕐 $(now_utc) | $(now_local)
📍 Host: $(hostname)"
  else
    log "❌ Node $LICENSE FAILED to restart!"
    send_telegram "❌ <b>Node ${LICENSE} Failed to Restart</b>
⚠️ Manual intervention required!
📅 Last alive: <b>${WENT_DOWN_UTC}</b>
🕐 $(now_utc)
📍 Host: $(hostname)"
  fi
}

# ============================================================
# Heartbeat
# ============================================================

should_send_heartbeat() {
  [ ! -f "$HEARTBEAT_FILE" ] && return 0
  local DIFF=$(( $(date "+%s") - $(cat "$HEARTBEAT_FILE") ))
  [ "$DIFF" -ge 3600 ] && return 0
  return 1
}

send_heartbeat() {
  local LINES=""
  for LICENSE in "${LICENSES[@]}"; do
    if is_node_running "$LICENSE"; then
      local PID=$(get_node_pid "$LICENSE")
      local UP=$(get_node_uptime "$LICENSE")
      local RC=$(get_restart_count "$LICENSE")
      local PEN=$(get_penalty_count "$LICENSE")
      local ICON="🟢"; [ "$PEN" -ge "$PENALTY_WARN" ] && ICON="🟡"; [ "$PEN" -ge "$PENALTY_CRITICAL" ] && ICON="🟠"
      LINES="${LINES}🟢 <code>${LICENSE}</code> — PID <code>${PID}</code> — Up: <b>${UP}</b> — Restarts: <b>${RC}</b> — ${ICON} Penalties: <b>${PEN}/${PENALTY_MAX}</b>\n"
      save_pid "$LICENSE" "$PID"
      update_last_seen "$LICENSE"
    else
      LINES="${LINES}🔴 <code>${LICENSE}</code> — DOWN\n"
    fi
  done
  send_telegram "💓 <b>DeNet Node Monitor HeartBeat</b>
📍 Host: $(hostname)
🕐 $(now_utc) | $(now_local)

<b>Node Status:</b>
$(echo -e "$LINES")"
  date "+%s" > "$HEARTBEAT_FILE"
  log "Heartbeat sent."
}

# ============================================================
# Main
# ============================================================

log "========== DeNet Monitor Run Started =========="
DOWN=0

for LICENSE in "${LICENSES[@]}"; do
  if is_node_running "$LICENSE"; then
    PID=$(get_node_pid "$LICENSE")
    UPTIME=$(get_node_uptime "$LICENSE")
    log "✅ Node $LICENSE running (PID: $PID, Uptime: $UPTIME)"
    # Save PID every run — ensures PID file is always fresh
    save_pid "$LICENSE" "$PID"
    update_last_seen "$LICENSE"
  else
    log "⚠️ Node $LICENSE DOWN — restarting..."
    DOWN=$((DOWN + 1))
    send_telegram "⚠️ <b>DeNet Node Down Detected</b>
🔑 License: <code>${LICENSE}</code>
🕐 $(now_utc)
📍 Host: $(hostname)"
    restart_node "$LICENSE"
  fi
done

[ "$DOWN" -eq 0 ] && log "All nodes running." || log "$DOWN node(s) restarted."
should_send_heartbeat && send_heartbeat
log "========== DeNet Monitor Run Finished =========="
