#!/bin/bash

# ============================================================
# DeNet Telegram Bot Listener
# User: maqbool | Ubuntu VM
# Runs as a systemd service — always alive, instant response
# v1.0
# ============================================================

# --- Telegram Config ---
TELEGRAM_BOT_TOKEN="YOUR_TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="YOUR_TELEGRAM_CHAT_ID"

# --- Node Config ---
DENODE_BIN="/usr/bin/denode"
WALLET_ADDRESS="YOUR_WALLET_ADDRESS"
LICENSES=(YOUR_LICENSE_1 YOUR_LICENSE_2 YOUR_LICENSE_3)

# --- Paths ---
NODE_LOG_DIR="$HOME/.denode/logs"
RESTART_COUNT_FILE="$HOME/.denode/.restart_counts"
PID_STATE_FILE="$HOME/.denode/.node_pids"
LAST_SEEN_FILE="$HOME/.denode/.node_last_seen"
DOWNTIME_LOG="$HOME/.denode/.node_downtime_log"
PENALTY_FILE="$HOME/.denode/.node_penalties"
PENALTY_MAX=10
OFFSET_FILE="$HOME/.denode/.bot_offset"
BOT_LOG="$HOME/.denode/bot-listener.log"

# --- Timezone Config ---
# Set your local timezone. Examples:
# "Asia/Kolkata" (India), "Europe/Berlin" (Germany),
# "America/New_York" (US East), "Asia/Manila" (Philippines)
LOCAL_TIMEZONE="YOUR_TIMEZONE"  # e.g. Asia/Kolkata, Europe/Berlin, America/New_York, Asia/Manila

mkdir -p "$NODE_LOG_DIR"
touch "$RESTART_COUNT_FILE" "$PID_STATE_FILE" "$LAST_SEEN_FILE" "$DOWNTIME_LOG" "$PENALTY_FILE"

# ============================================================
# Time
# ============================================================

now_utc() { date -u '+%Y-%m-%d %H:%M:%S UTC'; }
now_local() { TZ="${LOCAL_TIMEZONE}" date '+%H:%M:%S %Z'; }

# ============================================================
# Logging
# ============================================================

log() {
  echo "[$(now_utc) | $(now_local)] $1" | tee -a "$BOT_LOG"
}

# ============================================================
# Node Helpers
# ============================================================

is_node_running() {
  local LICENSE="$1"
  ps aux | grep -v grep | grep "$DENODE_BIN" | grep -- "--license $LICENSE" > /dev/null 2>&1
}

get_node_pid() {
  local LICENSE="$1"
  ps aux | grep -v grep | grep "$DENODE_BIN" | grep -- "--license $LICENSE" | awk '{print $2}' | head -n 1
}

get_node_uptime() {
  local LICENSE="$1"
  local PID
  PID=$(get_node_pid "$LICENSE")
  [ -z "$PID" ] && echo "not running" && return

  local ETIME
  ETIME=$(ps -o etime= -p "$PID" 2>/dev/null | tr -d ' ')
  [ -z "$ETIME" ] && echo "unknown" && return

  local DAYS=0 HOURS=0 MINS=0
  if echo "$ETIME" | grep -q '-'; then
    DAYS=$(echo "$ETIME" | cut -d'-' -f1)
    ETIME=$(echo "$ETIME" | cut -d'-' -f2)
  fi

  local PARTS
  IFS=':' read -ra PARTS <<< "$ETIME"
  case ${#PARTS[@]} in
    3) HOURS=${PARTS[0]}; MINS=${PARTS[1]} ;;
    2) MINS=${PARTS[0]} ;;
  esac

  DAYS=$((10#$DAYS)); HOURS=$((10#$HOURS)); MINS=$((10#$MINS))

  local RESULT=""
  [ "$DAYS"  -gt 0 ] && RESULT="${DAYS}d "
  [ "$HOURS" -gt 0 ] && RESULT="${RESULT}${HOURS}h "
  [ "$MINS"  -gt 0 ] && RESULT="${RESULT}${MINS}m"
  [ -z "$RESULT"   ] && RESULT="&lt; 1m"
  echo "$RESULT"
}

# ============================================================
# Restart Counter
# ============================================================

get_restart_count() {
  local LICENSE="$1"
  local COUNT
  COUNT=$(grep "^${LICENSE}=" "$RESTART_COUNT_FILE" 2>/dev/null | cut -d= -f2)
  echo "${COUNT:-0}"
}

get_penalty_count() {
  local LICENSE="$1"
  local VAL
  VAL=$(grep "^${LICENSE}=" "$PENALTY_FILE" 2>/dev/null | cut -d= -f2)
  echo "${VAL:-0}"
}

reset_penalty_count() {
  local LICENSE="$1"
  sed -i "/^${LICENSE}=/d" "$PENALTY_FILE" 2>/dev/null
  echo "${LICENSE}=0" >> "$PENALTY_FILE"
}

increment_restart_count() {
  local LICENSE="$1"
  local CURRENT NEW_COUNT
  CURRENT=$(get_restart_count "$LICENSE")
  NEW_COUNT=$(( CURRENT + 1 ))
  sed -i "/^${LICENSE}=/d" "$RESTART_COUNT_FILE" 2>/dev/null
  echo "${LICENSE}=${NEW_COUNT}" >> "$RESTART_COUNT_FILE"
}

reset_restart_counts() {
  > "$RESTART_COUNT_FILE"
  log "Restart counts reset."
}

# ============================================================
# PID Tracking & Downtime Functions
# (shared state files with denet-monitor.sh)
# ============================================================

get_saved_pid() {
  local LICENSE="$1"
  local VAL
  VAL=$(grep "^${LICENSE}=" "$PID_STATE_FILE" 2>/dev/null | cut -d= -f2)
  echo "${VAL:-}"
}

get_last_seen() {
  local LICENSE="$1"
  local VAL
  VAL=$(grep "^${LICENSE}=" "$LAST_SEEN_FILE" 2>/dev/null | cut -d= -f2)
  echo "${VAL:-}"
}

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

# Returns downtime info for a node if its PID changed
get_pid_change_info() {
  local LICENSE="$1"
  local CURRENT_PID
  CURRENT_PID=$(get_node_pid "$LICENSE")
  local SAVED_PID
  SAVED_PID=$(get_saved_pid "$LICENSE")

  if [ -n "$SAVED_PID" ] && [ -n "$CURRENT_PID" ] && [ "$SAVED_PID" != "$CURRENT_PID" ]; then
    local LAST_SEEN NOW OFFLINE_SECS OFFLINE_DURATION WENT_DOWN_UTC
    LAST_SEEN=$(get_last_seen "$LICENSE")
    NOW=$(date +%s)
    if [ -n "$LAST_SEEN" ]; then
      OFFLINE_SECS=$(( NOW - LAST_SEEN ))
      OFFLINE_DURATION=$(format_duration "$OFFLINE_SECS")
      WENT_DOWN_UTC=$(date -u -d "@${LAST_SEEN}" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || \
                      date -u -r "$LAST_SEEN" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null)
    else
      OFFLINE_DURATION="unknown"
      WENT_DOWN_UTC="unknown"
    fi
    echo "CHANGED|${SAVED_PID}|${CURRENT_PID}|${WENT_DOWN_UTC}|${OFFLINE_DURATION}"
  else
    echo "SAME"
  fi
}

# Get last downtime event for a node from the log
get_last_downtime() {
  local LICENSE="$1"
  if [ ! -f "$DOWNTIME_LOG" ]; then echo "No history yet."; return; fi
  local LAST
  LAST=$(grep "^${LICENSE}|" "$DOWNTIME_LOG" 2>/dev/null | tail -1)
  if [ -z "$LAST" ]; then echo "No recorded downtime."; return; fi
  local RESTART_AT WENT_DOWN DURATION OLD_PID NEW_PID
  RESTART_AT=$(echo "$LAST" | cut -d'|' -f2)
  WENT_DOWN=$(echo  "$LAST" | cut -d'|' -f3)
  DURATION=$(echo   "$LAST" | cut -d'|' -f4)
  OLD_PID=$(echo    "$LAST" | cut -d'|' -f5)
  NEW_PID=$(echo    "$LAST" | cut -d'|' -f6)

  # Convert UTC timestamps to IST for display
  local WENT_DOWN_LOCAL="" RESTART_AT_LOCAL=""
  if [ "$WENT_DOWN" != "unknown" ] && [ -n "$WENT_DOWN" ]; then
    WENT_DOWN_LOCAL=$(TZ="${LOCAL_TIMEZONE}" date -d "$WENT_DOWN" '+%H:%M %Z' 2>/dev/null || echo "")
    [ -n "$WENT_DOWN_LOCAL" ] && WENT_DOWN_LOCAL=" (${WENT_DOWN_LOCAL})"
  fi
  if [ -n "$RESTART_AT" ]; then
    RESTART_AT_LOCAL=$(TZ="${LOCAL_TIMEZONE}" date -d "$RESTART_AT" '+%H:%M %Z' 2>/dev/null || echo "")
    [ -n "$RESTART_AT_LOCAL" ] && RESTART_AT_LOCAL=" (${RESTART_AT_LOCAL})"
  fi

  echo "📅 Last down: ${WENT_DOWN}${WENT_DOWN_LOCAL}
⏱ Offline: ${DURATION}
🔄 Restarted: ${RESTART_AT}${RESTART_AT_LOCAL}
🆔 PID: ${OLD_PID}→${NEW_PID}"
}

# ============================================================
# Telegram
# ============================================================

send_message() {
  local CHAT_ID="$1"
  local TEXT="$2"
  curl -s --max-time 15 -X POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${CHAT_ID}" \
    -d text="${TEXT}" \
    -d parse_mode="HTML" > /dev/null 2>&1
}

get_updates() {
  local OFFSET="$1"
  curl -s --max-time 35 \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates?offset=${OFFSET}&limit=10&timeout=30"
}

# ============================================================
# Command Handlers
# ============================================================

cmd_status() {
  local CHAT_ID="$1"
  local LINES=""
  local RESTART_SECTION=""
  local HAS_ALERT=0

  for LICENSE in "${LICENSES[@]}"; do
    if is_node_running "$LICENSE"; then
      local PID UPTIME RC
      PID=$(get_node_pid "$LICENSE")
      UPTIME=$(get_node_uptime "$LICENSE")
      RC=$(get_restart_count "$LICENSE")

      # Check for silent PID change
      local PID_INFO
      PID_INFO=$(get_pid_change_info "$LICENSE")

      if [ "$PID_INFO" != "SAME" ]; then
        local OLD_PID WENT_DOWN OFFLINE_DUR
        OLD_PID=$(echo "$PID_INFO" | cut -d'|' -f2)
        WENT_DOWN=$(echo "$PID_INFO" | cut -d'|' -f4)
        OFFLINE_DUR=$(echo "$PID_INFO" | cut -d'|' -f5)
        LINES="${LINES}⚠️ <code>${LICENSE}</code> — PID <code>${PID}</code> — Up: <b>${UPTIME}</b> — Restarts: <b>${RC}</b>\n"
        RESTART_SECTION="${RESTART_SECTION}⚠️ <code>${LICENSE}</code> restarted silently!\n"
        RESTART_SECTION="${RESTART_SECTION}   🔴 Old PID: <code>${OLD_PID}</code> → 🟢 New: <code>${PID}</code>\n"
        RESTART_SECTION="${RESTART_SECTION}   📅 Last alive: <b>${WENT_DOWN}</b>\n"
        RESTART_SECTION="${RESTART_SECTION}   ⏱ Offline for: <b>${OFFLINE_DUR}</b>\n"
        HAS_ALERT=1
      else
        LINES="${LINES}🟢 <code>${LICENSE}</code> — PID <code>${PID}</code> — Up: <b>${UPTIME}</b> — Restarts: <b>${RC}</b>\n"
      fi
    else
      local RC LAST_SEEN_TS LAST_SEEN_STR
      RC=$(get_restart_count "$LICENSE")
      LAST_SEEN_TS=$(get_last_seen "$LICENSE")
      if [ -n "$LAST_SEEN_TS" ]; then
        LAST_SEEN_STR=$(date -u -d "@${LAST_SEEN_TS}" '+%H:%M UTC' 2>/dev/null || \
                        date -u -r "$LAST_SEEN_TS" '+%H:%M UTC' 2>/dev/null)
        LINES="${LINES}🔴 <code>${LICENSE}</code> — <b>DOWN</b> — Last seen: ${LAST_SEEN_STR} — Restarts: <b>${RC}</b>\n"
      else
        LINES="${LINES}🔴 <code>${LICENSE}</code> — <b>DOWN</b> — Restarts: <b>${RC}</b>\n"
      fi
    fi
  done

  local ALERT_BLOCK=""
  [ "$HAS_ALERT" -eq 1 ] && ALERT_BLOCK="
⚠️ <b>Silent Restarts Detected:</b>
$(echo -e "$RESTART_SECTION")"

  send_message "$CHAT_ID" "📊 <b>DeNet Node Monitor HeartBeat</b>
🕐 $(now_utc)
🕐 $(now_local)
📍 Host: $(hostname)
${ALERT_BLOCK}
<b>Node Status:</b>
$(echo -e "$LINES")"
}

cmd_restarts() {
  local CHAT_ID="$1"
  local LINES=""
  for LICENSE in "${LICENSES[@]}"; do
    local COUNT ICON
    COUNT=$(get_restart_count "$LICENSE")
    ICON="🟢"
    [ "$COUNT" -gt 0 ] && ICON="🔄"
    [ "$COUNT" -ge 5 ] && ICON="🔴"
    LINES="${LINES}${ICON} Node <code>${LICENSE}</code> — <b>${COUNT}</b> restart(s)\n"
  done

  send_message "$CHAT_ID" "🔄 <b>DeNet Node Restart Counts</b>
🕐 $(now_utc)
📍 Host: $(hostname)

$(echo -e "$LINES")
<i>Use /resetcounts to reset all to zero</i>"
}

cmd_restart_node() {
  local CHAT_ID="$1"
  local LICENSE="$2"

  # Validate license
  local VALID=0
  for L in "${LICENSES[@]}"; do
    [ "$L" = "$LICENSE" ] && VALID=1 && break
  done

  if [ "$VALID" -eq 0 ]; then
    send_message "$CHAT_ID" "❌ <b>Unknown license:</b> <code>${LICENSE}</code>

Valid licenses: 1072, 1864, 1865, 1866, 1867, 2157"
    return
  fi

  send_message "$CHAT_ID" "🔄 <b>Restarting Node ${LICENSE}...</b>
🕐 $(now_utc)
📍 Host: $(hostname)

<i>Please wait...</i>"

  log "Manual restart requested for node $LICENSE"

  # Kill existing process
  local OLD_PID
  OLD_PID=$(get_node_pid "$LICENSE")
  if [ -n "$OLD_PID" ]; then
    kill "$OLD_PID" 2>/dev/null
    sleep 2
  fi

  # Start node
  nohup "$DENODE_BIN" \
    --address "$WALLET_ADDRESS" \
    --license "$LICENSE" \
    >> "$NODE_LOG_DIR/node-${LICENSE}.log" 2>&1 &

  sleep 4

  if is_node_running "$LICENSE"; then
    local NEW_PID
    NEW_PID=$(get_node_pid "$LICENSE")
    increment_restart_count "$LICENSE"
    local TOTAL
    TOTAL=$(get_restart_count "$LICENSE")
    log "Node $LICENSE restarted successfully (PID: $NEW_PID, Total restarts: $TOTAL)"
    send_message "$CHAT_ID" "✅ <b>Node ${LICENSE} Restarted</b>
🆔 New PID: <code>${NEW_PID}</code>
🔄 Total Restarts: <b>${TOTAL}</b>
🕐 $(now_utc)
🕐 $(now_local)
📍 Host: $(hostname)

ℹ️ Restart is free while node is in pool"
  else
    log "Node $LICENSE FAILED to restart!"
    send_message "$CHAT_ID" "❌ <b>Node ${LICENSE} Failed to Restart!</b>
🕐 $(now_utc)
📍 Host: $(hostname)

⚠️ Manual intervention required on the VM."
  fi
}

cmd_restart_all() {
  local CHAT_ID="$1"

  send_message "$CHAT_ID" "🔄 <b>Restarting ALL 6 Nodes...</b>
🕐 $(now_utc)
📍 Host: $(hostname)

ℹ️ Nodes will restart — <b>free while in pool</b>
<i>Starting restart sequence...</i>"

  log "Manual restart ALL requested"

  local SUCCESS=0 FAILED=0

  for LICENSE in "${LICENSES[@]}"; do
    local OLD_PID
    OLD_PID=$(get_node_pid "$LICENSE")
    [ -n "$OLD_PID" ] && kill "$OLD_PID" 2>/dev/null && sleep 1

    nohup "$DENODE_BIN" \
      --address "$WALLET_ADDRESS" \
      --license "$LICENSE" \
      >> "$NODE_LOG_DIR/node-${LICENSE}.log" 2>&1 &

    sleep 4

    if is_node_running "$LICENSE"; then
      increment_restart_count "$LICENSE"
      SUCCESS=$((SUCCESS + 1))
      log "Node $LICENSE restarted OK"
    else
      FAILED=$((FAILED + 1))
      log "Node $LICENSE FAILED to restart"
    fi
  done

  local RESULT_LINES=""
  for LICENSE in "${LICENSES[@]}"; do
    if is_node_running "$LICENSE"; then
      local PID RC
      PID=$(get_node_pid "$LICENSE")
      RC=$(get_restart_count "$LICENSE")
      RESULT_LINES="${RESULT_LINES}✅ <code>${LICENSE}</code> — PID <code>${PID}</code> — Restarts: <b>${RC}</b>\n"
    else
      RESULT_LINES="${RESULT_LINES}❌ <code>${LICENSE}</code> — FAILED\n"
    fi
  done

  send_message "$CHAT_ID" "$([ "$FAILED" -eq 0 ] && echo "✅" || echo "⚠️") <b>Restart All Complete</b>
✅ Success: <b>${SUCCESS}/6</b>
$([ "$FAILED" -gt 0 ] && echo "❌ Failed: <b>${FAILED}/6</b>")
🕐 $(now_utc)
🕐 $(now_local)
📍 Host: $(hostname)

$(echo -e "$RESULT_LINES")"
}

cmd_reset_counts() {
  local CHAT_ID="$1"
  reset_restart_counts
  send_message "$CHAT_ID" "✅ <b>All restart counts reset to 0</b>
🕐 $(now_utc)
📍 Host: $(hostname)"
}

cmd_disk() {
  local CHAT_ID="$1"
  local LINES=""
  local STORAGE_DRIVES=(
    "YOUR_STORAGE_PATH/YOUR_LICENSE_1"
    "YOUR_STORAGE_PATH/YOUR_LICENSE_2"
    "YOUR_STORAGE_PATH/YOUR_LICENSE_3"
    "YOUR_STORAGE_PATH/YOUR_LICENSE_4"
    "YOUR_STORAGE_PATH/YOUR_LICENSE_5"
    "YOUR_STORAGE_PATH/YOUR_LICENSE_6"
  )

  for DRIVE in "${STORAGE_DRIVES[@]}"; do
    if [ ! -d "$DRIVE" ]; then
      LINES="${LINES}❌ $(basename $DRIVE) — NOT MOUNTED\n"
      continue
    fi
    local USAGE USED TOTAL FREE ICON
    USAGE=$(df "$DRIVE" | awk 'NR==2 {gsub("%",""); print $5}')
    USED=$(df -h "$DRIVE" | awk 'NR==2 {print $3}')
    TOTAL=$(df -h "$DRIVE" | awk 'NR==2 {print $2}')
    FREE=$(df -h "$DRIVE" | awk 'NR==2 {print $4}')
    ICON="🟢"
    [ "$USAGE" -ge 85 ] && ICON="🔴"
    [ "$USAGE" -ge 70 ] && [ "$USAGE" -lt 85 ] && ICON="🟡"
    LINES="${LINES}${ICON} <code>$(basename $DRIVE)</code>: ${USAGE}% — ${USED}/${TOTAL} (free: ${FREE})\n"
  done

  send_message "$CHAT_ID" "💾 <b>DeNet Disk Usage</b>
🕐 $(now_utc)
📍 Host: $(hostname)

$(echo -e "$LINES")"
}

cmd_version() {
  local CHAT_ID="$1"
  local VER
  VER=$("$DENODE_BIN" --version 2>/dev/null | head -1 || echo "unknown")
  send_message "$CHAT_ID" "📦 <b>DeNet Node Version</b>
🔢 Version: <code>${VER}</code>
📍 Host: $(hostname)
🕐 $(now_utc)"
}

cmd_history() {
  local CHAT_ID="$1"
  local LINES=""

  for LICENSE in "${LICENSES[@]}"; do
    local INFO RC
    INFO=$(get_last_downtime "$LICENSE")
    RC=$(get_restart_count "$LICENSE")
    LINES="${LINES}🔑 <code>${LICENSE}</code> — Restarts: <b>${RC}</b>\n   └ ${INFO}\n"
  done

  send_message "$CHAT_ID" "📋 <b>DeNet Node Downtime History</b>
🕐 $(now_utc)
📍 Host: $(hostname)

$(echo -e "$LINES")
<i>Use /history for last event per node</i>"
}

cmd_penalties() {
  local CHAT_ID="$1"
  local LINES=""
  local HAS_ISSUES=0

  for LICENSE in "${LICENSES[@]}"; do
    local COUNT ICON STATUS_MSG
    COUNT=$(get_penalty_count "$LICENSE")

    if   [ "$COUNT" -eq 0 ];  then ICON="🟢"; STATUS_MSG="Clean"
    elif [ "$COUNT" -lt 5 ];  then ICON="🟡"; STATUS_MSG="Watch"
    elif [ "$COUNT" -lt 8 ];  then ICON="🟠"; STATUS_MSG="Warning! $(( PENALTY_MAX - COUNT )) cycles left"
                                   HAS_ISSUES=1
    elif [ "$COUNT" -lt 10 ]; then ICON="🔴"; STATUS_MSG="CRITICAL! $(( PENALTY_MAX - COUNT )) cycle(s) left"
                                   HAS_ISSUES=1
    else                           ICON="🚫"; STATUS_MSG="Pool removal threshold reached"
                                   HAS_ISSUES=1
    fi

    LINES="${LINES}${ICON} <code>${LICENSE}</code> — <b>${COUNT}/${PENALTY_MAX}</b> — ${STATUS_MSG}\n"
  done

  local FOOTER=""
  [ "$HAS_ISSUES" -eq 1 ] && FOOTER="\n⚠️ <i>Penalties reset to 0 after a successful proof cycle</i>"

  send_message "$CHAT_ID" "📊 <b>DeNet Node Penalty Status</b>
🕐 $(now_utc)
📍 Host: $(hostname)

$(echo -e "$LINES")
<b>Scale:</b> 0=Clean · 5=Watch · 8=Critical · 10=Pool removed
<i>~90 min per cycle · 10 missed cycles ≈ 15 hours</i>${FOOTER}"
}

cmd_help() {
  local CHAT_ID="$1"
  send_message "$CHAT_ID" "🤖 <b>DeNet Node Monitor Bot</b>
📍 Host: $(hostname)

🔄 <b>Restart Commands:</b>
/restart 1072 — Restart a specific node
/restartall — Restart all nodes
ℹ️ Restart is free while node is in pool

📊 <b>Status Commands:</b>
/status — Live status with PID change detection
/restarts — Restart count per node
/penalties — Penalty count per node
/history — Last downtime event per node
/disk — Storage drive usage
/version — Current denode binary version

🔧 <b>Utility:</b>
/resetcounts — Reset all restart counters to 0
/help — Show this message"
}

# ============================================================
# Main Loop — Long Polling
# ============================================================

log "=========================================="
log "  DeNet Bot Listener Started"
log "  Host: $(hostname)"
log "=========================================="

send_message "$TELEGRAM_CHAT_ID" "🤖 <b>DeNet Node Monitor Bot Started</b>
📍 Host: $(hostname)
🕐 $(now_utc)
🕐 $(now_local)

Ready to receive commands. Send /help for the list."

OFFSET=0
if [ -f "$OFFSET_FILE" ]; then
  OFFSET=$(cat "$OFFSET_FILE")
fi

while true; do
  UPDATES=$(get_updates "$OFFSET")

  # Check for valid response
  if ! echo "$UPDATES" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('ok') else 1)" 2>/dev/null; then
    log "⚠️ Telegram API error or timeout — retrying in 5s..."
    sleep 5
    continue
  fi

  # Process updates
  RESULT=$(echo "$UPDATES" | python3 -c "
import json, sys

data = json.load(sys.stdin)
results = data.get('result', [])

for update in results:
    uid = update.get('update_id', 0)
    msg = update.get('message', {})
    chat_id = str(msg.get('chat', {}).get('id', ''))
    text = msg.get('text', '').strip()
    print(f'{uid}|{chat_id}|{text}')
" 2>/dev/null)

  while IFS='|' read -r UPDATE_ID CHAT_ID TEXT; do
    [ -z "$UPDATE_ID" ] && continue

    # Update offset
    NEXT_OFFSET=$(( UPDATE_ID + 1 ))
    [ "$NEXT_OFFSET" -gt "$OFFSET" ] && OFFSET="$NEXT_OFFSET"

    # Only handle messages from authorized chat
    if [ "$CHAT_ID" != "$TELEGRAM_CHAT_ID" ]; then
      log "Ignored message from unauthorized chat: $CHAT_ID"
      continue
    fi

    TEXT_LOWER="${TEXT,,}"
    log "Command received: $TEXT"

    case "$TEXT_LOWER" in
      /status|/s)
        cmd_status "$CHAT_ID"
        ;;
      /restarts|/restart_counts|/rc)
        cmd_restarts "$CHAT_ID"
        ;;
      /penalties|/penalty|/pen)
        cmd_penalties "$CHAT_ID"
        ;;
      /restartall|/restart_all)
        cmd_restart_all "$CHAT_ID"
        ;;
      /resetcounts|/reset_counts)
        cmd_reset_counts "$CHAT_ID"
        ;;
      /disk|/storage)
        cmd_disk "$CHAT_ID"
        ;;
      /history|/h)
        cmd_history "$CHAT_ID"
        ;;
      /version|/ver)
        cmd_version "$CHAT_ID"
        ;;
      /help|/start)
        cmd_help "$CHAT_ID"
        ;;
      /restart\ *)
        LICENSE=$(echo "$TEXT" | awk '{print $2}')
        cmd_restart_node "$CHAT_ID" "$LICENSE"
        ;;
      *)
        # Unknown command
        if echo "$TEXT" | grep -q '^/'; then
          send_message "$CHAT_ID" "❓ Unknown command: <code>${TEXT}</code>
Send /help for the list of commands."
        fi
        ;;
    esac

  done <<< "$RESULT"

  # Save offset
  echo "$OFFSET" > "$OFFSET_FILE"

done
