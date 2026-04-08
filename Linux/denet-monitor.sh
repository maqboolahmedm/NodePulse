#!/bin/bash

# ============================================================
# DeNet Node Monitor & Auto-Restart Script
# User: maqbool | Ubuntu VM
# v4.0 — Per-node uptime, configurable timezone, DuckDNS, port/RPC per node
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
LICENSES=(YOUR_LICENSE_1 YOUR_LICENSE_2 YOUR_LICENSE_3)

# Per-node ports (from manager_config.yaml)
declare -A NODE_PORT
NODE_PORT[YOUR_LICENSE_1]=55050
NODE_PORT[YOUR_LICENSE_2]=55056
NODE_PORT[YOUR_LICENSE_3]=55051
NODE_PORT[YOUR_LICENSE_4]=55053
NODE_PORT[YOUR_LICENSE_5]=55057
NODE_PORT[YOUR_LICENSE_6]=55055

# Per-node private RPC endpoints (from manager_config.yaml)
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
mkdir -p "$NODE_LOG_DIR" "$(dirname $STATUS_JSON)" 2>/dev/null || true
touch "$PID_STATE_FILE" "$LAST_SEEN_FILE" "$DOWNTIME_LOG" "$PENALTY_FILE"

# --- Penalty Config ---
PENALTY_WARN=5       # Warn at this many penalties
PENALTY_CRITICAL=8   # Critical alert at this many
PENALTY_MAX=10       # Removed from pool at this many
CYCLE_MINUTES=90     # Approximate cycle duration in minutes

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
# Set your local timezone. Examples:
# "Asia/Kolkata" (India), "Europe/Berlin" (Germany),
# "America/New_York" (US East), "Asia/Manila" (Philippines),
# "America/Los_Angeles" (US West), "Asia/Singapore"
LOCAL_TIMEZONE="YOUR_TIMEZONE"  # e.g. Asia/Kolkata, Europe/Berlin, America/New_York, Asia/Manila

# --- Display ---
export DISPLAY=:0
export XAUTHORITY="$HOME/.Xauthority"
export DENODE_PASSWORD="YOUR_NODE_PASSWORD"

# ============================================================
# Time Functions — UTC and IST displayed together
# ============================================================

now_utc() {
  date -u '+%Y-%m-%d %H:%M:%S UTC'
}

now_local() {
  TZ="${LOCAL_TIMEZONE}" date '+%H:%M:%S %Z'
}

now_both() {
  echo "$(now_utc) | $(now_local)"
}

# ============================================================
# Core Functions
# ============================================================

log() {
  echo "[$(now_utc) | $(now_local)] $1" | tee -a "$LOG_FILE"
}

send_telegram() {
  local MESSAGE="$1"
  local RESPONSE
  RESPONSE=$(curl -s --max-time 15 -X POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    -d text="${MESSAGE}" \
    -d parse_mode="HTML" 2>&1)

  if echo "$RESPONSE" | grep -q '"ok":false'; then
    log "⚠️  Telegram API error: $RESPONSE"
  elif [ -z "$RESPONSE" ]; then
    log "⚠️  Telegram: No response (network issue?)"
  fi
}

is_node_running() {
  local LICENSE="$1"
  ps aux | grep -v grep | grep "$DENODE_BIN" | grep -- "--license $LICENSE" > /dev/null 2>&1
  return $?
}

get_node_pid() {
  local LICENSE="$1"
  ps aux | grep -v grep | grep "$DENODE_BIN" | grep -- "--license $LICENSE" | awk '{print $2}' | head -n 1
}

# Returns how long a node process has been running e.g. "2d 5h 14m" or "45m"
get_node_uptime() {
  local LICENSE="$1"
  local PID
  PID=$(get_node_pid "$LICENSE")
  if [ -z "$PID" ]; then
    echo "not running"
    return
  fi

  # ps etime format: [[DD-]HH:]MM:SS
  local ETIME
  ETIME=$(ps -o etime= -p "$PID" 2>/dev/null | tr -d ' ')

  if [ -z "$ETIME" ]; then
    echo "unknown"
    return
  fi

  # Parse DD-HH:MM:SS or HH:MM:SS or MM:SS
  local DAYS=0 HOURS=0 MINS=0 SECS=0

  if echo "$ETIME" | grep -q '-'; then
    DAYS=$(echo "$ETIME" | cut -d'-' -f1)
    ETIME=$(echo "$ETIME" | cut -d'-' -f2)
  fi

  local PARTS
  IFS=':' read -ra PARTS <<< "$ETIME"

  case ${#PARTS[@]} in
    3) HOURS=${PARTS[0]}; MINS=${PARTS[1]}; SECS=${PARTS[2]} ;;
    2) MINS=${PARTS[0]}; SECS=${PARTS[1]} ;;
    1) SECS=${PARTS[0]} ;;
  esac

  # Remove leading zeros
  DAYS=$((10#$DAYS))
  HOURS=$((10#$HOURS))
  MINS=$((10#$MINS))

  local RESULT=""
  [ "$DAYS"  -gt 0 ] && RESULT="${DAYS}d "
  [ "$HOURS" -gt 0 ] && RESULT="${RESULT}${HOURS}h "
  [ "$MINS"  -gt 0 ] && RESULT="${RESULT}${MINS}m"
  [ -z "$RESULT"   ] && RESULT="< 1m"

  echo "$RESULT"
}

restart_node() {
  local LICENSE="$1"
  local OLD_PID

  # Try live process first, fall back to saved PID file
  OLD_PID=$(get_node_pid "$LICENSE")
  if [ -z "$OLD_PID" ]; then
    OLD_PID=$(get_saved_pid "$LICENSE")
  fi

  # Calculate downtime before restart
  local LAST_SEEN OFFLINE_DURATION WENT_DOWN_UTC
  LAST_SEEN=$(get_last_seen "$LICENSE")
  if [ -n "$LAST_SEEN" ]; then
    local NOW
    NOW=$(date +%s)
    local OFFLINE_SECS=$(( NOW - LAST_SEEN ))
    OFFLINE_DURATION=$(format_duration "$OFFLINE_SECS")
    WENT_DOWN_UTC=$(date -u -d "@${LAST_SEEN}" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || \
                    date -u -r "$LAST_SEEN" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null)
  else
    OFFLINE_DURATION="unknown"
    WENT_DOWN_UTC="unknown"
  fi

  log "Restarting node $LICENSE (last seen alive: ${WENT_DOWN_UTC}, offline ~${OFFLINE_DURATION})..."
  nohup "$DENODE_BIN" \
    --address "$WALLET_ADDRESS" \
    --license "$LICENSE" \
    >> "$NODE_LOG_DIR/node-${LICENSE}.log" 2>&1 &
  sleep 3
  if is_node_running "$LICENSE"; then
    local NEW_PID
    NEW_PID=$(get_node_pid "$LICENSE")
    increment_restart_count "$LICENSE"
    local TOTAL_RESTARTS
    TOTAL_RESTARTS=$(get_restart_count "$LICENSE")
    # Update PID state and last seen
    save_pid "$LICENSE" "$NEW_PID"
    update_last_seen "$LICENSE"
    # Log downtime event
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
# Restart Counter Functions
# ============================================================

increment_restart_count() {
  local LICENSE="$1"
  local CURRENT
  CURRENT=$(get_restart_count "$LICENSE")
  local NEW_COUNT=$(( CURRENT + 1 ))
  if [ -f "$RESTART_COUNT_FILE" ]; then
    sed -i "/^${LICENSE}=/d" "$RESTART_COUNT_FILE"
  fi
  echo "${LICENSE}=${NEW_COUNT}" >> "$RESTART_COUNT_FILE"
}

get_restart_count() {
  local LICENSE="$1"
  if [ ! -f "$RESTART_COUNT_FILE" ]; then
    echo "0"
    return
  fi
  local COUNT
  COUNT=$(grep "^${LICENSE}=" "$RESTART_COUNT_FILE" 2>/dev/null | cut -d= -f2)
  echo "${COUNT:-0}"
}

get_all_restart_counts() {
  local LINES=""
  for LIC in "${LICENSES[@]}"; do
    local COUNT
    COUNT=$(get_restart_count "$LIC")
    local ICON="🟢"
    [ "$COUNT" -gt 0 ] && ICON="🔄"
    [ "$COUNT" -ge 5 ] && ICON="🔴"
    LINES="${LINES}${ICON} Node <code>${LIC}</code> — restarted <b>${COUNT}</b> time(s)\n"
  done
  echo -e "$LINES"
}

reset_restart_counts() {
  > "$RESTART_COUNT_FILE"
  log "🔄 Restart counts reset."
}

# ============================================================
# PID Tracking & Downtime Functions
# ============================================================

get_saved_pid() {
  local LICENSE="$1"
  local VAL
  VAL=$(grep "^${LICENSE}=" "$PID_STATE_FILE" 2>/dev/null | cut -d= -f2)
  echo "${VAL:-}"
}

save_pid() {
  local LICENSE="$1"
  local PID="$2"
  sed -i "/^${LICENSE}=/d" "$PID_STATE_FILE" 2>/dev/null
  echo "${LICENSE}=${PID}" >> "$PID_STATE_FILE"
}

update_last_seen() {
  local LICENSE="$1"
  local NOW
  NOW=$(date +%s)
  sed -i "/^${LICENSE}=/d" "$LAST_SEEN_FILE" 2>/dev/null
  echo "${LICENSE}=${NOW}" >> "$LAST_SEEN_FILE"
}

get_last_seen() {
  local LICENSE="$1"
  local VAL
  VAL=$(grep "^${LICENSE}=" "$LAST_SEEN_FILE" 2>/dev/null | cut -d= -f2)
  echo "${VAL:-}"
}

# Format seconds into "Xh Ym" or "Xm"
format_duration() {
  local SECS="$1"
  local DAYS=$(( SECS / 86400 ))
  local HOURS=$(( (SECS % 86400) / 3600 ))
  local MINS=$(( (SECS % 3600) / 60 ))
  local RESULT=""
  [ "$DAYS"  -gt 0 ] && RESULT="${DAYS}d "
  [ "$HOURS" -gt 0 ] && RESULT="${RESULT}${HOURS}h "
  RESULT="${RESULT}${MINS}m"
  echo "$RESULT"
}

# Called when a PID change is detected — records downtime event
record_downtime_event() {
  local LICENSE="$1"
  local OLD_PID="$2"
  local NEW_PID="$3"
  local LAST_SEEN
  LAST_SEEN=$(get_last_seen "$LICENSE")
  local NOW
  NOW=$(date +%s)
  local WENT_DOWN_AT="unknown"
  local DOWNTIME_DURATION="unknown"
  local WENT_DOWN_UTC="unknown"

  if [ -n "$LAST_SEEN" ]; then
    # Node was last confirmed alive at LAST_SEEN
    # It went down sometime between LAST_SEEN and NOW
    # Best estimate: midpoint, but we report last-seen time
    WENT_DOWN_AT="$LAST_SEEN"
    WENT_DOWN_UTC=$(date -u -d "@${LAST_SEEN}" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || \
                    date -u -r "$LAST_SEEN" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null)
    local OFFLINE_SECS=$(( NOW - LAST_SEEN ))
    DOWNTIME_DURATION=$(format_duration "$OFFLINE_SECS")
  fi

  # Save to downtime log
  echo "${LICENSE}|$(date -u '+%Y-%m-%d %H:%M:%S UTC')|${WENT_DOWN_UTC}|${DOWNTIME_DURATION}|${OLD_PID}|${NEW_PID}" >> "$DOWNTIME_LOG"

  echo "$WENT_DOWN_UTC|$DOWNTIME_DURATION"
}

# Check if PID changed since last heartbeat — returns info string if changed
check_pid_change() {
  local LICENSE="$1"
  local CURRENT_PID
  CURRENT_PID=$(get_node_pid "$LICENSE")
  local SAVED_PID
  SAVED_PID=$(get_saved_pid "$LICENSE")

  if [ -n "$SAVED_PID" ] && [ -n "$CURRENT_PID" ] && [ "$SAVED_PID" != "$CURRENT_PID" ]; then
    # PID changed — node was restarted silently
    local INFO
    INFO=$(record_downtime_event "$LICENSE" "$SAVED_PID" "$CURRENT_PID")
    local WENT_DOWN
    WENT_DOWN=$(echo "$INFO" | cut -d'|' -f1)
    local DURATION
    DURATION=$(echo "$INFO" | cut -d'|' -f2)
    echo "RESTARTED|${SAVED_PID}|${CURRENT_PID}|${WENT_DOWN}|${DURATION}"
  else
    echo "OK"
  fi
}

# NOTE: Telegram command handling moved to denet-bot-listener.sh (systemd service)

# ============================================================
# Penalty Tracking Functions
# ============================================================

get_penalty_count() {
  local LICENSE="$1"
  local VAL
  VAL=$(grep "^${LICENSE}=" "$PENALTY_FILE" 2>/dev/null | cut -d= -f2)
  echo "${VAL:-0}"
}

set_penalty_count() {
  local LICENSE="$1"
  local COUNT="$2"
  sed -i "/^${LICENSE}=/d" "$PENALTY_FILE" 2>/dev/null
  echo "${LICENSE}=${COUNT}" >> "$PENALTY_FILE"
}

increment_penalty() {
  local LICENSE="$1"
  local CURRENT
  CURRENT=$(get_penalty_count "$LICENSE")
  local NEW=$(( CURRENT + 1 ))
  set_penalty_count "$LICENSE" "$NEW"
  echo "$NEW"
}

reset_penalty() {
  local LICENSE="$1"
  set_penalty_count "$LICENSE" "0"
  log "✅ Node $LICENSE penalties reset to 0 (successful proof cycle)"
}

# Check node logs for proof submission or missed cycle
# Returns: "PROOF_OK", "MISSED", or "UNKNOWN"
check_proof_status() {
  local LICENSE="$1"
  local LOG_A="$NODE_LOG_DIR/license-${LICENSE}.log"
  local LOG_B="$NODE_LOG_DIR/node-${LICENSE}.log"
  local NODE_LOG=""

  if   [ -f "$LOG_A" ]; then NODE_LOG="$LOG_A"
  elif [ -f "$LOG_B" ]; then NODE_LOG="$LOG_B"
  else echo "UNKNOWN"; return; fi

  # Check recent logs for proof submission success
  local RECENT
  RECENT=$(tail -100 "$NODE_LOG" 2>/dev/null)

  # DeNet RC12 log patterns for successful proof
  if echo "$RECENT" | grep -qiE "proof sent|proof submitted|storage proof|proof_of_storage|sendProof|proofsent"; then
    echo "PROOF_OK"
    return
  fi

  # Patterns for missed cycle / penalty
  if echo "$RECENT" | grep -qiE "missed|penalty|failed to send proof|proof failed|deadline exceeded"; then
    echo "MISSED"
    return
  fi

  echo "UNKNOWN"
}

# Full penalty check — call every cron run
check_and_update_penalties() {
  local LICENSE="$1"
  if ! is_node_running "$LICENSE"; then
    return  # Node is down — handled by restart logic
  fi

  local PROOF_STATUS
  PROOF_STATUS=$(check_proof_status "$LICENSE")
  local CURRENT_PENALTIES
  CURRENT_PENALTIES=$(get_penalty_count "$LICENSE")

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
    local NEW_PENALTIES
    NEW_PENALTIES=$(increment_penalty "$LICENSE")
    log "⚠️ Node $LICENSE missed proof cycle — penalties: ${NEW_PENALTIES}/${PENALTY_MAX}"

    # Warning at threshold
    if [ "$NEW_PENALTIES" -eq "$PENALTY_WARN" ]; then
      send_telegram "⚠️ <b>Node ${LICENSE} — Penalty Warning</b>
🔑 License: <code>${LICENSE}</code>
📊 Penalties: <b>${NEW_PENALTIES}/${PENALTY_MAX}</b>
⏱ ~$(( (PENALTY_MAX - NEW_PENALTIES) * CYCLE_MINUTES / 60 ))h before pool removal
💡 Monitor closely — if next cycle fails, penalties increase
🕐 $(now_utc) | $(now_local)
📍 Host: $(hostname)"

    # Critical alert
    elif [ "$NEW_PENALTIES" -ge "$PENALTY_CRITICAL" ]; then
      send_telegram "🚨 <b>Node ${LICENSE} — CRITICAL Penalty Alert</b>
🔑 License: <code>${LICENSE}</code>
📊 Penalties: <b>${NEW_PENALTIES}/${PENALTY_MAX}</b>
⚠️ Only $(( PENALTY_MAX - NEW_PENALTIES )) cycle(s) before pool removal!
🔄 Consider restarting node now
🕐 $(now_utc) | $(now_local)
📍 Host: $(hostname)"

    # Pool removal
    elif [ "$NEW_PENALTIES" -ge "$PENALTY_MAX" ]; then
      send_telegram "🚫 <b>Node ${LICENSE} — REMOVED FROM POOL</b>
🔑 License: <code>${LICENSE}</code>
📊 Penalties reached: <b>${NEW_PENALTIES}/${PENALTY_MAX}</b>
🔄 Restarting node — will auto re-join pool...
🕐 $(now_utc) | $(now_local)
📍 Host: $(hostname)"
      # Auto restart to trigger re-join
      local OLD_PID
      OLD_PID=$(get_node_pid "$LICENSE")
      [ -n "$OLD_PID" ] && kill "$OLD_PID" 2>/dev/null && sleep 2
      restart_node "$LICENSE"
      set_penalty_count "$LICENSE" "0"
    fi
  fi
}

get_penalty_summary() {
  local LINES=""
  for LIC in "${LICENSES[@]}"; do
    local COUNT ICON
    COUNT=$(get_penalty_count "$LIC")
    if   [ "$COUNT" -eq 0 ];                      then ICON="🟢"
    elif [ "$COUNT" -lt "$PENALTY_WARN" ];         then ICON="🟡"
    elif [ "$COUNT" -lt "$PENALTY_CRITICAL" ];     then ICON="🟠"
    else                                                ICON="🔴"
    fi
    LINES="${LINES}${ICON} Node <code>${LIC}</code> — <b>${COUNT}/${PENALTY_MAX}</b> penalties\n"
  done
  echo -e "$LINES"
}

# ============================================================
# DuckDNS Update
# ============================================================

update_duckdns() {
  local RESULT
  RESULT=$(curl -s --max-time 10 \
    "https://www.duckdns.org/update?domains=${DUCKDNS_DOMAIN}&token=${DUCKDNS_TOKEN}&ip=")
  if [ "$RESULT" = "OK" ]; then
    log "🌐 DuckDNS updated successfully."
  else
    log "⚠️  DuckDNS update failed: $RESULT"
  fi
}

# ============================================================
# Feature 1 — Disk Space Monitoring
# ============================================================

check_disk_space() {
  for DRIVE in "${STORAGE_DRIVES[@]}"; do
    if [ ! -d "$DRIVE" ]; then
      log "⚠️  Drive $DRIVE not found or not mounted!"
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
    USED=$(df -h "$DRIVE"  | awk 'NR==2 {print $3}')
    FREE=$(df -h "$DRIVE"  | awk 'NR==2 {print $4}')

    log "💾 $DRIVE — ${USAGE}% used (${USED}/${TOTAL}, free: ${FREE})"

    if [ "$USAGE" -ge "$DISK_ALERT_THRESHOLD" ]; then
      log "⚠️  Drive $DRIVE at ${USAGE}% — exceeds threshold!"
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
      SUMMARY="${SUMMARY}❌ $(basename $DRIVE) — NOT MOUNTED\n"
      continue
    fi
    local USAGE USED TOTAL FREE
    USAGE=$(df "$DRIVE" | awk 'NR==2 {gsub("%",""); print $5}')
    USED=$(df -h "$DRIVE"  | awk 'NR==2 {print $3}')
    TOTAL=$(df -h "$DRIVE" | awk 'NR==2 {print $2}')
    FREE=$(df -h "$DRIVE"  | awk 'NR==2 {print $4}')
    local ICON="🟢"
    [ "$USAGE" -ge "$DISK_ALERT_THRESHOLD" ] && ICON="🔴"
    SUMMARY="${SUMMARY}${ICON} $(basename $DRIVE): ${USAGE}% — ${USED}/${TOTAL} (free: ${FREE})\n"
  done
  echo -e "$SUMMARY"
}

# ============================================================
# Feature 2 — Log Error Alerts
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

  if [ -f "$LOG_A" ]; then
    NODE_LOG="$LOG_A"
  elif [ -f "$LOG_B" ]; then
    NODE_LOG="$LOG_B"
  else
    return
  fi

  local RECENT_LINES
  RECENT_LINES=$(tail -50 "$NODE_LOG" 2>/dev/null)

  for PATTERN_ENTRY in "${ERROR_PATTERNS[@]}"; do
    local PATTERN="${PATTERN_ENTRY%%|*}"
    local LABEL="${PATTERN_ENTRY##*|}"

    if echo "$RECENT_LINES" | grep -qi "$PATTERN"; then
      local STATE_KEY="${LICENSE}_${PATTERN// /_}"
      local LAST_ALERTED=""

      if [ -f "$ERROR_STATE_FILE" ]; then
        LAST_ALERTED=$(grep "^${STATE_KEY}=" "$ERROR_STATE_FILE" 2>/dev/null | cut -d= -f2)
      fi

      local NOW
      NOW=$(date +%s)
      local ALERT_INTERVAL=3600

      if [ -z "$LAST_ALERTED" ] || [ $(( NOW - LAST_ALERTED )) -ge "$ALERT_INTERVAL" ]; then
        local ERROR_LINE
        ERROR_LINE=$(echo "$RECENT_LINES" | grep -i "$PATTERN" | tail -1)

        log "⚠️  Node $LICENSE — $LABEL detected"
        send_telegram "⚠️ <b>DeNet Node Error Detected</b>
🔑 License: <code>${LICENSE}</code>
🔴 Error: <b>${LABEL}</b>
📋 Detail: <code>${ERROR_LINE}</code>
🕐 $(now_utc)
🕐 $(now_local)
📍 Host: $(hostname)

<i>Node process is still running. This may auto-resolve.</i>"

        if [ -f "$ERROR_STATE_FILE" ]; then
          sed -i "/^${STATE_KEY}=/d" "$ERROR_STATE_FILE" 2>/dev/null
        fi
        echo "${STATE_KEY}=${NOW}" >> "$ERROR_STATE_FILE"
      fi
    fi
  done
}

# ============================================================
# Feature 3 — Daily Summary Report
# ============================================================

send_daily_summary() {
  local STATUS_LINES=""
  local UP_COUNT=0 DOWN_COUNT=0

  for LICENSE in "${LICENSES[@]}"; do
    if is_node_running "$LICENSE"; then
      local PID UPTIME
      PID=$(get_node_pid "$LICENSE")
      UPTIME=$(get_node_uptime "$LICENSE")
      STATUS_LINES="${STATUS_LINES}🟢 <code>${LICENSE}</code> — PID <code>${PID}</code> — Up: <b>${UPTIME}</b>\n"
      UP_COUNT=$(( UP_COUNT + 1 ))
    else
      STATUS_LINES="${STATUS_LINES}🔴 <code>${LICENSE}</code> — DOWN\n"
      DOWN_COUNT=$(( DOWN_COUNT + 1 ))
    fi
  done

  local DISK_INFO OVERALL
  DISK_INFO=$(get_disk_summary)

  if [ "$DOWN_COUNT" -eq 0 ]; then
    OVERALL="✅ All 6 nodes healthy"
  else
    OVERALL="⚠️ ${DOWN_COUNT} node(s) are DOWN"
  fi

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

  if [ ! -f "$DAILY_SUMMARY_FILE" ]; then
    return 0
  fi
  local LAST NOW DIFF
  LAST=$(cat "$DAILY_SUMMARY_FILE")
  NOW=$(date +%s)
  DIFF=$(( NOW - LAST ))
  [ "$DIFF" -lt 82800 ] && return 1
  return 0
}

# ============================================================
# Hourly Heartbeat
# ============================================================

send_heartbeat() {
  local STATUS_LINES=""
  local RESTART_ALERT_LINES=""
  local HAS_RESTART_ALERT=0

  for LICENSE in "${LICENSES[@]}"; do
    if is_node_running "$LICENSE"; then
      local PID UPTIME RC
      PID=$(get_node_pid "$LICENSE")
      UPTIME=$(get_node_uptime "$LICENSE")
      RC=$(get_restart_count "$LICENSE")

      # Check if PID changed since last heartbeat
      local PID_CHECK
      PID_CHECK=$(check_pid_change "$LICENSE")

      if [ "$PID_CHECK" != "OK" ]; then
        # PID changed — silent restart detected
        local OLD_PID WENT_DOWN OFFLINE_DURATION
        OLD_PID=$(echo "$PID_CHECK" | cut -d'|' -f2)
        WENT_DOWN=$(echo "$PID_CHECK" | cut -d'|' -f4)
        OFFLINE_DURATION=$(echo "$PID_CHECK" | cut -d'|' -f5)
        local PENALTIES
        PENALTIES=$(get_penalty_count "$LICENSE")

        STATUS_LINES="${STATUS_LINES}⚠️ <code>${LICENSE}</code> — PID <code>${PID}</code> — Up: <b>${UPTIME}</b> — Restarts: <b>${RC}</b> — Penalties: <b>${PENALTIES}/${PENALTY_MAX}</b>\n"
        RESTART_ALERT_LINES="${RESTART_ALERT_LINES}⚠️ Node <code>${LICENSE}</code> was restarted silently!\n"
        RESTART_ALERT_LINES="${RESTART_ALERT_LINES}   🔴 Old PID: <code>${OLD_PID}</code> → 🟢 New PID: <code>${PID}</code>\n"
        RESTART_ALERT_LINES="${RESTART_ALERT_LINES}   📅 Last seen alive: <b>${WENT_DOWN}</b>\n"
        RESTART_ALERT_LINES="${RESTART_ALERT_LINES}   ⏱ Was offline for: <b>${OFFLINE_DURATION}</b>\n"
        HAS_RESTART_ALERT=1
        log "⚠️ PID change detected for node $LICENSE: $OLD_PID → $PID (offline ~${OFFLINE_DURATION})"
      else
        local PENALTIES
        PENALTIES=$(get_penalty_count "$LICENSE")
        local PENALTY_ICON="🟢"
        [ "$PENALTIES" -ge "$PENALTY_WARN" ]     && PENALTY_ICON="🟡"
        [ "$PENALTIES" -ge "$PENALTY_CRITICAL" ] && PENALTY_ICON="🟠"
        STATUS_LINES="${STATUS_LINES}🟢 <code>${LICENSE}</code> — PID <code>${PID}</code> — Up: <b>${UPTIME}</b> — Restarts: <b>${RC}</b> — ${PENALTY_ICON} Penalties: <b>${PENALTIES}/${PENALTY_MAX}</b>\n"
      fi

      # Update saved PID and last seen timestamp
      save_pid "$LICENSE" "$PID"
      update_last_seen "$LICENSE"

    else
      local RC
      RC=$(get_restart_count "$LICENSE")
      STATUS_LINES="${STATUS_LINES}🔴 <code>${LICENSE}</code> — <b>DOWN</b> — Restarts: <b>${RC}</b>\n"
      # Don't update last_seen — it's down
    fi
  done

  local DISK_INFO
  DISK_INFO=$(get_disk_summary)

  # Build restart section only if there were silent restarts
  local RESTART_SECTION=""
  if [ "$HAS_RESTART_ALERT" -eq 1 ]; then
    RESTART_SECTION="
⚠️ <b>Silent Restart Detected:</b>
$(echo -e "$RESTART_ALERT_LINES")"
  fi

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
  LAST=$(cat "$HEARTBEAT_FILE")
  NOW=$(date +%s)
  DIFF=$(( NOW - LAST ))
  [ "$DIFF" -ge "$INTERVAL" ] && return 0
  return 1
}

# ============================================================
# NodePulse — Write status.json for PWA Dashboard
# ============================================================

write_status_json() {
  local DENODE_VERSION
  DENODE_VERSION=$("$DENODE_BIN" --version 2>/dev/null | head -1 || echo "unknown")

  python3 - <<PYEOF
import json, os, subprocess
from datetime import datetime, timezone

licenses  = [1072, 1864, 1865, 1866, 1867, 2157]
pid_file  = os.path.expanduser("$PID_STATE_FILE")
seen_file = os.path.expanduser("$LAST_SEEN_FILE")
rc_file   = os.path.expanduser("$RESTART_COUNT_FILE")
dt_log    = os.path.expanduser("$DOWNTIME_LOG")
pen_file  = os.path.expanduser("$PENALTY_FILE")
penalty_max = int("$PENALTY_MAX")
drives    = ["/mnt/Denet-Storage/" + str(l) for l in licenses]

def read_kv(path):
    out = {}
    try:
        for line in open(path):
            if "=" in line:
                k, v = line.strip().split("=", 1)
                out[k] = v
    except: pass
    return out

saved_pids  = read_kv(pid_file)
last_seen   = read_kv(seen_file)
restart_cnt = read_kv(rc_file)
penalties   = read_kv(pen_file)

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
                pid = parts[1]
                # get uptime
                r2 = subprocess.run(["ps", "-o", "etime=", "-p", pid],
                                     capture_output=True, text=True)
                etime = r2.stdout.strip()
                return pid, etime
    except: pass
    return None, None

def parse_etime(et):
    if not et: return "unknown"
    days, hours, mins = 0, 0, 0
    if "-" in et:
        days, et = et.split("-", 1)
        days = int(days)
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
        pct = int(parts[4].replace("%",""))
        return {"used": parts[2], "total": parts[1], "free": parts[3], "pct": pct}
    except: return None

now_ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
nodes = []
for lic in licenses:
    pid, etime = get_ps_info(lic)
    running   = pid is not None
    saved_pid = saved_pids.get(str(lic), "")
    pid_changed = saved_pid and pid and saved_pid != pid
    ls_ts = last_seen.get(str(lic), "")
    last_seen_str = ""
    if ls_ts:
        try:
            dt = datetime.fromtimestamp(int(ls_ts), tz=timezone.utc)
            last_seen_str = dt.strftime("%Y-%m-%d %H:%M:%S UTC")
        except: pass
    disk = get_disk(f"/mnt/Denet-Storage/{lic}")
    nodes.append({
        "license":        lic,
        "status":         "running" if running else "down",
        "pid":            pid or "",
        "uptime":         parse_etime(etime) if running else "",
        "restarts":       int(restart_cnt.get(str(lic), 0)),
        "penalties":      int(penalties.get(str(lic), 0)),
        "penalty_max":    penalty_max,
        "pid_changed":    bool(pid_changed),
        "old_pid":        saved_pid if pid_changed else "",
        "last_seen":      last_seen_str,
        "last_downtime":  get_last_downtime(lic),
        "disk":           disk
    })

data = {
    "app":     "NodePulse",
    "version": "${DENODE_VERSION}",
    "host":    "$(hostname)",
    "updated": now_ts,
    "nodes":   nodes
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
  if is_node_running "$LICENSE"; then
    PID=$(get_node_pid "$LICENSE")
    UPTIME=$(get_node_uptime "$LICENSE")
    log "✅ Node $LICENSE is running (PID: $PID, Uptime: $UPTIME)"
    # Save PID and last-seen every run — not just hourly
    # This ensures we always have the latest PID even before heartbeat
    save_pid "$LICENSE" "$PID"
    update_last_seen "$LICENSE"
  else
    log "⚠️  Node $LICENSE is DOWN — attempting restart..."
    DOWN_COUNT=$((DOWN_COUNT + 1))
    send_telegram "⚠️ <b>DeNet Node Down Detected</b>
🔑 License: <code>${LICENSE}</code>
🔄 Attempting restart...
🕐 $(now_utc)
🕐 $(now_local)
📍 Host: $(hostname)"
    restart_node "$LICENSE"
  fi
done

[ "$DOWN_COUNT" -eq 0 ] && log "All 6 nodes running normally." || log "$DOWN_COUNT node(s) were restarted."

# 3. Check disk space
check_disk_space

# 4. Check node logs for errors
log "--- Checking node logs for errors ---"
for LICENSE in "${LICENSES[@]}"; do
  check_node_errors "$LICENSE"
done

# 5. Check and update penalties
log "--- Checking proof cycles and penalties ---"
for LICENSE in "${LICENSES[@]}"; do
  check_and_update_penalties "$LICENSE"
  PENALTIES=$(get_penalty_count "$LICENSE")
  log "📊 Node $LICENSE — penalties: ${PENALTIES}/${PENALTY_MAX}"
done

# 5. Hourly heartbeat
if should_send_heartbeat; then
  send_heartbeat
fi

# 6. Daily summary
if should_send_daily_summary; then
  send_daily_summary
fi

# 7. Write status.json for NodePulse dashboard
write_status_json

log "========== DeNet Monitor Run Finished =========="
