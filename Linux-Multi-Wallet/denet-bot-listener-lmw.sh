#!/bin/bash

# ============================================================
# DeNet Telegram Bot Listener — Multi-Wallet Version
# NodePulse v2.0
# ============================================================

# --- Telegram Config ---
TELEGRAM_BOT_TOKEN="YOUR_TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="YOUR_TELEGRAM_CHAT_ID"

# --- Wallet Config (must match denet-monitor.sh) ---
WALLET_1_ADDRESS="YOUR_WALLET_1_ADDRESS"
WALLET_1_PASSWORD="YOUR_WALLET_1_PASSWORD"
WALLET_1_LICENSES=(YOUR_W1_LICENSE_1 YOUR_W1_LICENSE_2 YOUR_W1_LICENSE_3)

WALLET_2_ADDRESS="YOUR_WALLET_2_ADDRESS"
WALLET_2_PASSWORD="YOUR_WALLET_2_PASSWORD"
WALLET_2_LICENSES=(YOUR_W2_LICENSE_1 YOUR_W2_LICENSE_2 YOUR_W2_LICENSE_3)

WALLET_3_ADDRESS=""
WALLET_3_PASSWORD=""
WALLET_3_LICENSES=()

WALLET_4_ADDRESS=""
WALLET_4_PASSWORD=""
WALLET_4_LICENSES=()

declare -A NODE_WALLET
declare -A NODE_STORAGE

# Wallet 1 nodes
NODE_WALLET[YOUR_W1_LICENSE_1]="$WALLET_1_ADDRESS"
NODE_STORAGE[YOUR_W1_LICENSE_1]="YOUR_STORAGE_PATH/YOUR_W1_LICENSE_1"
NODE_WALLET[YOUR_W1_LICENSE_2]="$WALLET_1_ADDRESS"
NODE_STORAGE[YOUR_W1_LICENSE_2]="YOUR_STORAGE_PATH/YOUR_W1_LICENSE_2"
NODE_WALLET[YOUR_W1_LICENSE_3]="$WALLET_1_ADDRESS"
NODE_STORAGE[YOUR_W1_LICENSE_3]="YOUR_STORAGE_PATH/YOUR_W1_LICENSE_3"

# Wallet 2 nodes
NODE_WALLET[YOUR_W2_LICENSE_1]="$WALLET_2_ADDRESS"
NODE_STORAGE[YOUR_W2_LICENSE_1]="YOUR_STORAGE_PATH/YOUR_W2_LICENSE_1"
NODE_WALLET[YOUR_W2_LICENSE_2]="$WALLET_2_ADDRESS"
NODE_STORAGE[YOUR_W2_LICENSE_2]="YOUR_STORAGE_PATH/YOUR_W2_LICENSE_2"

# --- General Config ---
DENODE_BIN="/usr/bin/denode"
LOCAL_TIMEZONE="YOUR_TIMEZONE"

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

mkdir -p "$NODE_LOG_DIR"
touch "$RESTART_COUNT_FILE" "$PID_STATE_FILE" "$LAST_SEEN_FILE" "$DOWNTIME_LOG" "$PENALTY_FILE"

# Build combined license list
ALL_LICENSES=()
[ ${#WALLET_1_LICENSES[@]} -gt 0 ] && ALL_LICENSES+=("${WALLET_1_LICENSES[@]}")
[ ${#WALLET_2_LICENSES[@]} -gt 0 ] && ALL_LICENSES+=("${WALLET_2_LICENSES[@]}")
[ ${#WALLET_3_LICENSES[@]} -gt 0 ] && ALL_LICENSES+=("${WALLET_3_LICENSES[@]}")
[ ${#WALLET_4_LICENSES[@]} -gt 0 ] && ALL_LICENSES+=("${WALLET_4_LICENSES[@]}")

# ============================================================
# Helpers
# ============================================================
now_utc()   { date -u '+%Y-%m-%d %H:%M:%S UTC'; }
now_local() { TZ="${LOCAL_TIMEZONE}" date '+%H:%M:%S %Z'; }
log() { echo "[$(now_utc) | $(now_local)] $1" | tee -a "$BOT_LOG"; }

get_wallet_label() {
  local WALLET="${NODE_WALLET[$1]}"
  if   [ "$WALLET" = "$WALLET_1_ADDRESS" ]; then echo "W1"
  elif [ "$WALLET" = "$WALLET_2_ADDRESS" ]; then echo "W2"
  elif [ "$WALLET" = "$WALLET_3_ADDRESS" ]; then echo "W3"
  elif [ "$WALLET" = "$WALLET_4_ADDRESS" ]; then echo "W4"
  else echo "??"
  fi
}

get_wallet_password() {
  local WALLET="${NODE_WALLET[$1]}"
  if   [ "$WALLET" = "$WALLET_1_ADDRESS" ]; then echo "$WALLET_1_PASSWORD"
  elif [ "$WALLET" = "$WALLET_2_ADDRESS" ]; then echo "$WALLET_2_PASSWORD"
  elif [ "$WALLET" = "$WALLET_3_ADDRESS" ]; then echo "$WALLET_3_PASSWORD"
  elif [ "$WALLET" = "$WALLET_4_ADDRESS" ]; then echo "$WALLET_4_PASSWORD"
  fi
}

is_node_running() {
  ps aux | grep -v grep | grep "$DENODE_BIN" | grep -- "--license $1" > /dev/null 2>&1
}

get_node_pid() {
  ps aux | grep -v grep | grep "$DENODE_BIN" | grep -- "--license $1" | awk '{print $2}' | head -n 1
}

get_node_uptime() {
  local PID=$(get_node_pid "$1")
  [ -z "$PID" ] && echo "not running" && return
  local ETIME=$(ps -o etime= -p "$PID" 2>/dev/null | tr -d ' ')
  [ -z "$ETIME" ] && echo "unknown" && return
  local DAYS=0 HOURS=0 MINS=0
  echo "$ETIME" | grep -q '-' && DAYS=$(echo "$ETIME" | cut -d'-' -f1) && ETIME=$(echo "$ETIME" | cut -d'-' -f2)
  local PARTS; IFS=':' read -ra PARTS <<< "$ETIME"
  case ${#PARTS[@]} in 3) HOURS=${PARTS[0]}; MINS=${PARTS[1]} ;; 2) MINS=${PARTS[0]} ;; esac
  DAYS=$((10#$DAYS)); HOURS=$((10#$HOURS)); MINS=$((10#$MINS))
  local R=""
  [ "$DAYS"  -gt 0 ] && R="${DAYS}d "
  [ "$HOURS" -gt 0 ] && R="${R}${HOURS}h "
  [ "$MINS"  -gt 0 ] && R="${R}${MINS}m"
  [ -z "$R"         ] && R="&lt; 1m"
  echo "$R"
}

get_restart_count() {
  local C=$(grep "^${1}=" "$RESTART_COUNT_FILE" 2>/dev/null | cut -d= -f2)
  echo "${C:-0}"
}

increment_restart_count() {
  local NEW=$(( $(get_restart_count "$1") + 1 ))
  sed -i "/^${1}=/d" "$RESTART_COUNT_FILE" 2>/dev/null
  echo "${1}=${NEW}" >> "$RESTART_COUNT_FILE"
}

get_penalty_count() {
  local VAL=$(grep "^${1}=" "$PENALTY_FILE" 2>/dev/null | cut -d= -f2)
  echo "${VAL:-0}"
}

get_saved_pid() {
  local VAL=$(grep "^${1}=" "$PID_STATE_FILE" 2>/dev/null | cut -d= -f2)
  echo "${VAL:-}"
}

get_last_seen() {
  local VAL=$(grep "^${1}=" "$LAST_SEEN_FILE" 2>/dev/null | cut -d= -f2)
  echo "${VAL:-}"
}

format_duration() {
  local SECS="$1"
  local DAYS=$(( SECS/86400 )); local HOURS=$(( (SECS%86400)/3600 )); local MINS=$(( (SECS%3600)/60 ))
  local R=""
  [ "$DAYS"  -gt 0 ] && R="${DAYS}d "
  [ "$HOURS" -gt 0 ] && R="${R}${HOURS}h "
  R="${R}${MINS}m"; echo "$R"
}

get_last_downtime() {
  if [ ! -f "$DOWNTIME_LOG" ]; then echo "No history yet."; return; fi
  local LAST=$(grep "^${1}|" "$DOWNTIME_LOG" 2>/dev/null | tail -1)
  [ -z "$LAST" ] && echo "No recorded downtime." && return
  local RESTART_AT=$(echo "$LAST" | cut -d'|' -f2)
  local WENT_DOWN=$(echo "$LAST"  | cut -d'|' -f3)
  local DURATION=$(echo "$LAST"   | cut -d'|' -f4)
  local OLD_PID=$(echo "$LAST"    | cut -d'|' -f5)
  local NEW_PID=$(echo "$LAST"    | cut -d'|' -f6)
  local WENT_DOWN_LOCAL="" RESTART_AT_LOCAL=""
  [ "$WENT_DOWN" != "unknown" ] && WENT_DOWN_LOCAL=$(TZ="${LOCAL_TIMEZONE}" date -d "$WENT_DOWN" '+%H:%M %Z' 2>/dev/null) && [ -n "$WENT_DOWN_LOCAL" ] && WENT_DOWN_LOCAL=" (${WENT_DOWN_LOCAL})"
  [ -n "$RESTART_AT" ] && RESTART_AT_LOCAL=$(TZ="${LOCAL_TIMEZONE}" date -d "$RESTART_AT" '+%H:%M %Z' 2>/dev/null) && [ -n "$RESTART_AT_LOCAL" ] && RESTART_AT_LOCAL=" (${RESTART_AT_LOCAL})"
  echo "📅 Last down: ${WENT_DOWN}${WENT_DOWN_LOCAL}
⏱ Offline: ${DURATION}
🔄 Restarted: ${RESTART_AT}${RESTART_AT_LOCAL}
🆔 PID: ${OLD_PID}→${NEW_PID}"
}

# ============================================================
# Telegram
# ============================================================
send_message() {
  curl -s --max-time 15 -X POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${1}" -d text="${2}" -d parse_mode="HTML" > /dev/null 2>&1
}

get_updates() {
  curl -s --max-time 35 \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates?offset=${1}&limit=10&timeout=30"
}

# ============================================================
# Command Handlers
# ============================================================
cmd_status() {
  local CHAT_ID="$1"
  local W1="" W2="" W3="" W4=""
  for LICENSE in "${ALL_LICENSES[@]}"; do
    local WL=$(get_wallet_label "$LICENSE")
    local RC=$(get_restart_count "$LICENSE")
    local PEN=$(get_penalty_count "$LICENSE")
    local PEN_ICON="🟢"
    [ "$PEN" -ge 5 ] && PEN_ICON="🟡"
    [ "$PEN" -ge 8 ] && PEN_ICON="🔴"
    local LINE
    if is_node_running "$LICENSE"; then
      local PID=$(get_node_pid "$LICENSE"); local UP=$(get_node_uptime "$LICENSE")
      LINE="🟢 <code>${LICENSE}</code> — PID <code>${PID}</code> — Up: <b>${UP}</b> — R:<b>${RC}</b> — ${PEN_ICON}P:<b>${PEN}</b>\n"
    else
      LINE="🔴 <code>${LICENSE}</code> — <b>DOWN</b> — R:<b>${RC}</b>\n"
    fi
    case "$WL" in W1) W1="${W1}${LINE}" ;; W2) W2="${W2}${LINE}" ;; W3) W3="${W3}${LINE}" ;; W4) W4="${W4}${LINE}" ;; esac
  done
  local MSG="📊 <b>DeNet Node Status</b>
🕐 $(now_utc) | $(now_local)
📍 Host: $(hostname)
"
  [ -n "$W1" ] && MSG="${MSG}
<b>💼 Wallet 1:</b>
$(echo -e "$W1")"
  [ -n "$W2" ] && MSG="${MSG}
<b>💼 Wallet 2:</b>
$(echo -e "$W2")"
  [ -n "$W3" ] && MSG="${MSG}
<b>💼 Wallet 3:</b>
$(echo -e "$W3")"
  [ -n "$W4" ] && MSG="${MSG}
<b>💼 Wallet 4:</b>
$(echo -e "$W4")"
  send_message "$CHAT_ID" "$MSG"
}

cmd_penalties() {
  local CHAT_ID="$1"
  local W1="" W2="" W3="" W4=""
  for LICENSE in "${ALL_LICENSES[@]}"; do
    local WL=$(get_wallet_label "$LICENSE")
    local PEN=$(get_penalty_count "$LICENSE")
    local ICON="🟢"; local MSG_P="Clean"
    [ "$PEN" -ge 5 ]  && ICON="🟡" && MSG_P="Watch"
    [ "$PEN" -ge 8 ]  && ICON="🟠" && MSG_P="Warning!"
    [ "$PEN" -ge 10 ] && ICON="🔴" && MSG_P="CRITICAL!"
    local LINE="${ICON} <code>${LICENSE}</code> — <b>${PEN}/${PENALTY_MAX}</b> — ${MSG_P}\n"
    case "$WL" in W1) W1="${W1}${LINE}" ;; W2) W2="${W2}${LINE}" ;; W3) W3="${W3}${LINE}" ;; W4) W4="${W4}${LINE}" ;; esac
  done
  local MSG="📊 <b>Penalty Status</b>
🕐 $(now_utc) | $(now_local)
"
  [ -n "$W1" ] && MSG="${MSG}
<b>💼 Wallet 1:</b>
$(echo -e "$W1")"
  [ -n "$W2" ] && MSG="${MSG}
<b>💼 Wallet 2:</b>
$(echo -e "$W2")"
  [ -n "$W3" ] && MSG="${MSG}
<b>💼 Wallet 3:</b>
$(echo -e "$W3")"
  [ -n "$W4" ] && MSG="${MSG}
<b>💼 Wallet 4:</b>
$(echo -e "$W4")"
  send_message "$CHAT_ID" "$MSG"
}

cmd_restart_node() {
  local CHAT_ID="$1"; local LICENSE="$2"
  local VALID=0
  for L in "${ALL_LICENSES[@]}"; do [ "$L" = "$LICENSE" ] && VALID=1 && break; done
  if [ "$VALID" -eq 0 ]; then
    send_message "$CHAT_ID" "❌ Unknown license: <code>${LICENSE}</code>"; return
  fi
  local WL=$(get_wallet_label "$LICENSE")
  local WALLET="${NODE_WALLET[$LICENSE]}"
  local PASSWORD=$(get_wallet_password "$LICENSE")
  send_message "$CHAT_ID" "🔄 Restarting node <code>${LICENSE}</code> [<b>${WL}</b>]..."
  local OLD_PID=$(get_node_pid "$LICENSE")
  [ -z "$OLD_PID" ] && OLD_PID=$(get_saved_pid "$LICENSE")
  [ -n "$(get_node_pid $LICENSE)" ] && kill "$(get_node_pid $LICENSE)" 2>/dev/null && sleep 2
  export DENODE_PASSWORD="$PASSWORD"
  nohup "$DENODE_BIN" --address "$WALLET" --license "$LICENSE" \
    >> "$NODE_LOG_DIR/node-${LICENSE}.log" 2>&1 &
  sleep 4
  if is_node_running "$LICENSE"; then
    local NEW_PID=$(get_node_pid "$LICENSE")
    increment_restart_count "$LICENSE"
    local TOTAL=$(get_restart_count "$LICENSE")
    send_message "$CHAT_ID" "✅ <b>Node ${LICENSE} [${WL}] Restarted</b>
🆔 PID: <code>${OLD_PID:-unknown}</code> → <code>${NEW_PID}</code>
🔄 Total Restarts: <b>${TOTAL}</b>
ℹ️ Restart is free while node is in pool
🕐 $(now_utc) | $(now_local)"
  else
    send_message "$CHAT_ID" "❌ <b>Node ${LICENSE} [${WL}] FAILED!</b>
⚠️ Manual intervention required!"
  fi
}

cmd_restart_all() {
  local CHAT_ID="$1"
  send_message "$CHAT_ID" "🔄 <b>Restarting ALL ${#ALL_LICENSES[@]} nodes...</b>
ℹ️ Free while nodes are in pool"
  local SUCCESS=0 FAILED=0
  for LICENSE in "${ALL_LICENSES[@]}"; do
    local WALLET="${NODE_WALLET[$LICENSE]}"
    local PASSWORD=$(get_wallet_password "$LICENSE")
    local WL=$(get_wallet_label "$LICENSE")
    local OLD_PID=$(get_node_pid "$LICENSE")
    [ -n "$OLD_PID" ] && kill "$OLD_PID" 2>/dev/null && sleep 1
    export DENODE_PASSWORD="$PASSWORD"
    nohup "$DENODE_BIN" --address "$WALLET" --license "$LICENSE" \
      >> "$NODE_LOG_DIR/node-${LICENSE}.log" 2>&1 &
    sleep 3
    if is_node_running "$LICENSE"; then
      increment_restart_count "$LICENSE"
      SUCCESS=$(( SUCCESS + 1 ))
    else
      FAILED=$(( FAILED + 1 ))
    fi
  done
  local LINES=""
  for LICENSE in "${ALL_LICENSES[@]}"; do
    local WL=$(get_wallet_label "$LICENSE")
    if is_node_running "$LICENSE"; then
      local PID=$(get_node_pid "$LICENSE"); local RC=$(get_restart_count "$LICENSE")
      LINES="${LINES}✅ [${WL}] <code>${LICENSE}</code> — PID <code>${PID}</code> — R:<b>${RC}</b>\n"
    else
      LINES="${LINES}❌ [${WL}] <code>${LICENSE}</code> — FAILED\n"
    fi
  done
  send_message "$CHAT_ID" "$([ "$FAILED" -eq 0 ] && echo "✅" || echo "⚠️") <b>Restart All Complete</b>
✅ Success: <b>${SUCCESS}/${#ALL_LICENSES[@]}</b>
$([ "$FAILED" -gt 0 ] && echo "❌ Failed: <b>${FAILED}</b>")
🕐 $(now_utc) | $(now_local)

$(echo -e "$LINES")"
}

cmd_history() {
  local CHAT_ID="$1"
  local LINES=""
  for LICENSE in "${ALL_LICENSES[@]}"; do
    local WL=$(get_wallet_label "$LICENSE")
    local INFO=$(get_last_downtime "$LICENSE")
    local RC=$(get_restart_count "$LICENSE")
    LINES="${LINES}🔑 [<b>${WL}</b>] <code>${LICENSE}</code> — Restarts: <b>${RC}</b>\n   └ ${INFO}\n"
  done
  send_message "$CHAT_ID" "📋 <b>Downtime History</b>
🕐 $(now_utc) | $(now_local)
📍 Host: $(hostname)

$(echo -e "$LINES")"
}

cmd_disk() {
  local CHAT_ID="$1"
  local LINES=""
  for LICENSE in "${ALL_LICENSES[@]}"; do
    local WL=$(get_wallet_label "$LICENSE")
    local DRIVE="${NODE_STORAGE[$LICENSE]}"
    [ -z "$DRIVE" ] && continue
    if [ ! -d "$DRIVE" ]; then LINES="${LINES}❌ [${WL}] <code>${LICENSE}</code> — NOT MOUNTED\n"; continue; fi
    local USAGE=$(df "$DRIVE" | awk 'NR==2 {gsub("%",""); print $5}')
    local USED=$(df -h "$DRIVE" | awk 'NR==2 {print $3}')
    local TOTAL=$(df -h "$DRIVE" | awk 'NR==2 {print $2}')
    local FREE=$(df -h "$DRIVE" | awk 'NR==2 {print $4}')
    local ICON="🟢"; [ "$USAGE" -ge 85 ] && ICON="🔴"; [ "$USAGE" -ge 70 ] && [ "$USAGE" -lt 85 ] && ICON="🟡"
    LINES="${LINES}${ICON} [${WL}] <code>${LICENSE}</code>: ${USAGE}% — ${USED}/${TOTAL} (free: ${FREE})\n"
  done
  send_message "$CHAT_ID" "💾 <b>Disk Usage</b>
🕐 $(now_utc)
📍 Host: $(hostname)

$(echo -e "$LINES")"
}

cmd_restarts() {
  local CHAT_ID="$1"; local LINES=""
  for LICENSE in "${ALL_LICENSES[@]}"; do
    local WL=$(get_wallet_label "$LICENSE")
    local RC=$(get_restart_count "$LICENSE")
    local ICON="🟢"; [ "$RC" -gt 0 ] && ICON="🔄"; [ "$RC" -ge 5 ] && ICON="🔴"
    LINES="${LINES}${ICON} [${WL}] <code>${LICENSE}</code> — <b>${RC}</b> restart(s)\n"
  done
  send_message "$CHAT_ID" "🔄 <b>Restart Counts</b>
🕐 $(now_utc)
📍 Host: $(hostname)

$(echo -e "$LINES")
<i>Use /resetcounts to reset all to zero</i>"
}

cmd_version() {
  local CHAT_ID="$1"
  local VER=$("$DENODE_BIN" --version 2>/dev/null | head -1 || echo "unknown")
  send_message "$CHAT_ID" "📦 <b>DeNet Version</b>
🔢 Version: <code>${VER}</code>
📍 Host: $(hostname)
🕐 $(now_utc)"
}

cmd_reset_counts() {
  local CHAT_ID="$1"
  > "$RESTART_COUNT_FILE"
  send_message "$CHAT_ID" "✅ All restart counts reset to 0
🕐 $(now_utc)"
}

cmd_chain() {
  local CHAT_ID="$1"
  local W1_ADDR="${WALLET_1_ADDRESS:0:10}...${WALLET_1_ADDRESS: -6}"
  local W2_ADDR="${WALLET_2_ADDRESS:0:10}...${WALLET_2_ADDRESS: -6}"
  local MSG="⛓ <b>On-Chain Status</b>
🕐 $(now_utc) | $(now_local)

🔗 <b>Check transactions per wallet:</b>"
  [ -n "$WALLET_1_ADDRESS" ] && MSG="${MSG}
💼 <a href=\"https://peaq.subscan.io/account/${WALLET_1_ADDRESS}\">Wallet 1 — ${W1_ADDR}</a>"
  [ -n "$WALLET_2_ADDRESS" ] && MSG="${MSG}
💼 <a href=\"https://peaq.subscan.io/account/${WALLET_2_ADDRESS}\">Wallet 2 — ${W2_ADDR}</a>"
  [ -n "$WALLET_3_ADDRESS" ] && MSG="${MSG}
💼 <a href=\"https://peaq.subscan.io/account/${WALLET_3_ADDRESS}\">Wallet 3</a>"
  [ -n "$WALLET_4_ADDRESS" ] && MSG="${MSG}
💼 <a href=\"https://peaq.subscan.io/account/${WALLET_4_ADDRESS}\">Wallet 4</a>"
  MSG="${MSG}

<i>ONLINE = tx in last 4h
PENDING = 4–8h since last tx
OFFLINE = 8h+ no activity</i>"
  send_message "$CHAT_ID" "$MSG"
}

cmd_help() {
  local CHAT_ID="$1"
  send_message "$CHAT_ID" "🤖 <b>DeNet Node Monitor Bot</b>
📍 Host: $(hostname)
🔢 Wallets: $([ -n "$WALLET_1_ADDRESS" ] && echo W1) $([ -n "$WALLET_2_ADDRESS" ] && echo W2) $([ -n "$WALLET_3_ADDRESS" ] && echo W3) $([ -n "$WALLET_4_ADDRESS" ] && echo W4)
🔢 Total nodes: ${#ALL_LICENSES[@]}

🔄 <b>Restart:</b>
/restart 1072 — Restart specific node
/restartall — Restart all nodes
ℹ️ Free while node is in pool

📊 <b>Status:</b>
/status — All nodes grouped by wallet
/chain — On-chain TX links per wallet
/penalties — Penalty count per node
/restarts — Restart count per node
/history — Last downtime per node
/disk — Storage usage per node
/version — denode binary version

🔧 <b>Utility:</b>
/resetcounts — Reset restart counters
/help — Show this message"
}

# ============================================================
# Main Loop
# ============================================================
log "=========================================="
log "  DeNet Multi-Wallet Bot Started"
log "  Total nodes: ${#ALL_LICENSES[@]}"
log "=========================================="

send_message "$TELEGRAM_CHAT_ID" "🤖 <b>DeNet Multi-Wallet Bot Started</b>
📍 Host: $(hostname)
🔢 Wallets active: $([ -n "$WALLET_1_ADDRESS" ] && echo W1) $([ -n "$WALLET_2_ADDRESS" ] && echo W2) $([ -n "$WALLET_3_ADDRESS" ] && echo W3) $([ -n "$WALLET_4_ADDRESS" ] && echo W4)
🔢 Total nodes: ${#ALL_LICENSES[@]}
🕐 $(now_utc) | $(now_local)

Send /help for commands."

OFFSET=0
[ -f "$OFFSET_FILE" ] && OFFSET=$(cat "$OFFSET_FILE")

while true; do
  UPDATES=$(get_updates "$OFFSET")
  if ! echo "$UPDATES" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('ok') else 1)" 2>/dev/null; then
    sleep 5; continue
  fi
  RESULT=$(echo "$UPDATES" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for u in data.get('result',[]):
    uid = u.get('update_id',0)
    msg = u.get('message',{})
    cid = str(msg.get('chat',{}).get('id',''))
    txt = msg.get('text','').strip()
    print(f'{uid}|{cid}|{txt}')
" 2>/dev/null)

  while IFS='|' read -r UPDATE_ID CHAT_ID TEXT; do
    [ -z "$UPDATE_ID" ] && continue
    NEXT_OFFSET=$(( UPDATE_ID + 1 ))
    [ "$NEXT_OFFSET" -gt "$OFFSET" ] && OFFSET="$NEXT_OFFSET"
    [ "$CHAT_ID" != "$TELEGRAM_CHAT_ID" ] && continue
    TEXT_LOWER="${TEXT,,}"
    log "Command: $TEXT"
    case "$TEXT_LOWER" in
      /status|/s)            cmd_status "$CHAT_ID" ;;
      /chain|/txn)           cmd_chain "$CHAT_ID" ;;
      /penalties|/pen)       cmd_penalties "$CHAT_ID" ;;
      /restarts|/rc)         cmd_restarts "$CHAT_ID" ;;
      /restartall)           cmd_restart_all "$CHAT_ID" ;;
      /resetcounts)          cmd_reset_counts "$CHAT_ID" ;;
      /disk)                 cmd_disk "$CHAT_ID" ;;
      /history|/h)           cmd_history "$CHAT_ID" ;;
      /version)              cmd_version "$CHAT_ID" ;;
      /help|/start)          cmd_help "$CHAT_ID" ;;
      /restart\ *)           cmd_restart_node "$CHAT_ID" "$(echo "$TEXT" | awk '{print $2}')" ;;
      *) echo "$TEXT" | grep -q '^/' && send_message "$CHAT_ID" "❓ Unknown command. Send /help" ;;
    esac
  done <<< "$RESULT"

  echo "$OFFSET" > "$OFFSET_FILE"
done
