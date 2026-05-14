#!/bin/bash
# ============================================================
#  NodePulse Bot Listener — Single Wallet Edition
#  Version: 2.1.0 (RC14 compatible + /stop /start support)
#
#  Part of NodePulse — Community monitoring tool for DeNet nodes
#  GitHub: https://github.com/maqboolahmedm/NodePulse
#
#  Setup: Run nodepulse-setup.sh to configure automatically,
#         or replace placeholders manually before use.
# ============================================================

# ── CONFIG (replaced by setup wizard) ───────────────────────
TELEGRAM_BOT_TOKEN="NODEPULSE_BOT_TOKEN"
TELEGRAM_CHAT_ID="NODEPULSE_CHAT_ID"
WALLET="NODEPULSE_WALLET"
LICENSES=(NODEPULSE_LICENSES)

# ── PATHS ───────────────────────────────────────────────────
LOG_DIR="$HOME/.denode/logs"
PENALTIES_FILE="$HOME/.denode/.node_penalties"
GUARD_DIR="$HOME/.nodepulse_guard"
PAUSED_FILE="$GUARD_DIR/paused_nodes"
OFFSET_FILE="$HOME/.denode/.bot_offset"
BOT_LOG="$HOME/.denode/bot-listener.log"

# ── INIT ─────────────────────────────────────────────────────
mkdir -p "$GUARD_DIR" "$LOG_DIR"
touch "$PAUSED_FILE" "$PENALTIES_FILE"

# ── LOGGING ──────────────────────────────────────────────────
log() {
  echo "[$(date '+%m-%d %H:%M:%S')] $1" | tee -a "$BOT_LOG"
}

# ── TELEGRAM ─────────────────────────────────────────────────
send_message() {
  local MSG="$1"
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="$TELEGRAM_CHAT_ID" \
    -d parse_mode="HTML" \
    -d text="$MSG" > /dev/null
}

get_updates() {
  local OFFSET="${1:-0}"
  curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates?offset=${OFFSET}&timeout=30"
}

# ── HELPERS ──────────────────────────────────────────────────
is_valid_license() {
  local LIC="$1"
  for L in "${LICENSES[@]}"; do
    [[ "$L" == "$LIC" ]] && return 0
  done
  return 1
}

is_paused() {
  grep -qx "$1" "$PAUSED_FILE" 2>/dev/null
}

is_running() {
  ps aux | grep "license $1" | grep -v grep | grep -q denode
}

get_pid() {
  ps aux | grep "license $1" | grep -v grep | awk '{print $2}' | head -1
}

start_node() {
  local LIC="$1"
  local LOGFILE="$LOG_DIR/node-${LIC}.log"
  nohup /usr/bin/denode \
    --address "$WALLET" \
    --license "$LIC" >> "$LOGFILE" 2>&1 &
  echo $!
}

# ── COMMAND HANDLERS ─────────────────────────────────────────

cmd_help() {
  send_message "
<b>📡 NodePulse Commands</b>

/status — All node statuses
/logs &lt;license&gt; — Last 20 lines of node log
/penalties — Current penalty counts
/restart &lt;license&gt; — Restart a specific node
/stop &lt;license&gt; — Stop node + prevent auto-restart
/start &lt;license&gt; — Unpause and start node
/stopall — Stop all nodes
/startall — Start all stopped/paused nodes
/clearpenalties — Reset penalty file
/help — Show this menu"
}

cmd_status() {
  local RUNNING=0
  local PAUSED=0
  local STOPPED=0
  local MSG="<b>📊 NodePulse Status</b>\n"
  MSG+="<code>$(date '+%Y-%m-%d %H:%M:%S')</code>\n\n"

  for LIC in "${LICENSES[@]}"; do
    local PID SCORE PENALTY
    PID=$(get_pid "$LIC")

    SCORE=""
    [[ -f "$GUARD_DIR/score_$LIC" ]] && SCORE=" | Score: $(cat "$GUARD_DIR/score_$LIC")"

    PENALTY=$(grep "^${LIC}=" "$PENALTIES_FILE" 2>/dev/null | cut -d= -f2)
    [[ -n "$PENALTY" ]] && PENALTY=" | Pen: $PENALTY" || PENALTY=" | Pen: 0"

    if is_paused "$LIC"; then
      MSG+="🛑 <b>$LIC</b> — PAUSED${PENALTY}${SCORE}\n"
      ((PAUSED++))
    elif [[ -n "$PID" ]]; then
      MSG+="✅ <b>$LIC</b> — Running (PID $PID)${PENALTY}${SCORE}\n"
      ((RUNNING++))
    else
      MSG+="❌ <b>$LIC</b> — STOPPED${PENALTY}${SCORE}\n"
      ((STOPPED++))
    fi
  done

  MSG+="\n<b>Running:</b> $RUNNING | <b>Paused:</b> $PAUSED | <b>Stopped:</b> $STOPPED"
  send_message "$MSG"
}

cmd_logs() {
  local LIC="$1"
  if [[ -z "$LIC" ]]; then
    send_message "Usage: /logs &lt;license&gt;\nExample: /logs 2157"
    return
  fi
  if ! is_valid_license "$LIC"; then
    send_message "❌ Unknown license: $LIC"
    return
  fi
  local LOGFILE="$LOG_DIR/node-${LIC}.log"
  if [[ ! -f "$LOGFILE" ]]; then
    send_message "No log file found for node $LIC"
    return
  fi
  local LINES
  LINES=$(tail -20 "$LOGFILE" | sed 's/\x1b\[[0-9;]*m//g')
  send_message "<b>📋 Node $LIC — Last 20 lines</b>\n<pre>$LINES</pre>"
}

cmd_penalties() {
  local MSG="<b>⚠️ Node Penalties</b>\n\n"
  local ANY=0

  for LIC in "${LICENSES[@]}"; do
    local VAL
    VAL=$(grep "^${LIC}=" "$PENALTIES_FILE" 2>/dev/null | cut -d= -f2)
    if [[ -n "$VAL" && "$VAL" != "0" ]]; then
      MSG+="<b>$LIC</b>: $VAL penalties\n"
      ANY=1
    fi
  done

  [[ "$ANY" == "0" ]] && MSG+="✅ No penalties recorded."
  send_message "$MSG"
}

cmd_restart() {
  local LIC="$1"
  if [[ -z "$LIC" ]]; then
    send_message "Usage: /restart &lt;license&gt;"
    return
  fi
  if ! is_valid_license "$LIC"; then
    send_message "❌ Unknown license: $LIC"
    return
  fi
  if is_paused "$LIC"; then
    send_message "⏸️ Node $LIC is PAUSED. Use /start $LIC to resume it first."
    return
  fi

  send_message "🔄 Restarting node $LIC..."

  local OLD_PID
  OLD_PID=$(get_pid "$LIC")
  [[ -n "$OLD_PID" ]] && kill "$OLD_PID" && sleep 2

  local NEW_PID
  NEW_PID=$(start_node "$LIC")
  sleep 2

  if is_running "$LIC"; then
    send_message "✅ Node $LIC restarted (PID $NEW_PID)"
    log "Manual restart: $LIC (PID $NEW_PID)"
  else
    send_message "❌ Node $LIC failed to start — check /logs $LIC"
    log "Manual restart FAILED: $LIC"
  fi
}

cmd_stop() {
  local LIC="$1"
  if [[ -z "$LIC" ]]; then
    send_message "Usage: /stop &lt;license&gt;"
    return
  fi
  if ! is_valid_license "$LIC"; then
    send_message "❌ Unknown license: $LIC"
    return
  fi
  if is_paused "$LIC"; then
    send_message "ℹ️ Node $LIC is already paused."
    return
  fi

  # Mark paused FIRST — prevents monitor/guard race condition
  echo "$LIC" >> "$PAUSED_FILE"

  local PID
  PID=$(get_pid "$LIC")
  if [[ -n "$PID" ]]; then
    kill "$PID"
    sleep 1
    send_message "🛑 Node $LIC stopped and marked PAUSED.
Monitor and guard will not restart it until you run /start $LIC"
    log "Manual stop: $LIC (PID $PID)"
  else
    send_message "🛑 Node $LIC marked PAUSED (was not running)."
    log "Manual stop (not running): $LIC"
  fi
}

cmd_start() {
  local LIC="$1"
  if [[ -z "$LIC" ]]; then
    send_message "Usage: /start &lt;license&gt;"
    return
  fi
  if ! is_valid_license "$LIC"; then
    send_message "❌ Unknown license: $LIC"
    return
  fi

  # Remove from paused list
  sed -i "/^${LIC}$/d" "$PAUSED_FILE" 2>/dev/null

  if is_running "$LIC"; then
    send_message "⚠️ Node $LIC unpaused — already running (PID $(get_pid "$LIC"))"
    return
  fi

  send_message "▶️ Starting node $LIC..."
  local NEW_PID
  NEW_PID=$(start_node "$LIC")
  sleep 2

  if is_running "$LIC"; then
    send_message "✅ Node $LIC started (PID $NEW_PID). Monitoring resumed."
    log "Manual start: $LIC (PID $NEW_PID)"
  else
    send_message "❌ Node $LIC failed to start — check /logs $LIC"
    log "Manual start FAILED: $LIC"
  fi
}

cmd_stopall() {
  send_message "🛑 Stopping all nodes..."
  local COUNT=0
  for LIC in "${LICENSES[@]}"; do
    echo "$LIC" >> "$PAUSED_FILE"
    local PID
    PID=$(get_pid "$LIC")
    if [[ -n "$PID" ]]; then
      kill "$PID"
      ((COUNT++))
    fi
  done
  # Deduplicate paused file
  sort -u "$PAUSED_FILE" -o "$PAUSED_FILE"
  send_message "🛑 All nodes stopped and paused ($COUNT were running).
Use /startall or /start &lt;license&gt; to resume."
  log "Stop all: $COUNT nodes killed"
}

cmd_startall() {
  send_message "▶️ Starting all paused/stopped nodes..."
  > "$PAUSED_FILE"
  local COUNT=0
  for LIC in "${LICENSES[@]}"; do
    if ! is_running "$LIC"; then
      start_node "$LIC"
      ((COUNT++))
      sleep 1
    fi
  done
  sleep 3
  send_message "✅ Started $COUNT nodes. Use /status to verify."
  log "Start all: $COUNT nodes launched"
}

cmd_clearpenalties() {
  > "$PENALTIES_FILE"
  send_message "✅ Penalty file cleared."
  log "Penalties cleared via bot"
}

# ── DISPATCH ─────────────────────────────────────────────────
handle_command() {
  local TEXT="$1"
  log "CMD: $TEXT"

  local CMD ARG
  CMD=$(echo "$TEXT" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')
  ARG=$(echo "$TEXT" | awk '{print $2}')

  case "$CMD" in
    /help)           cmd_help ;;
    /status)         cmd_status ;;
    /logs)           cmd_logs "$ARG" ;;
    /penalties)      cmd_penalties ;;
    /restart)        cmd_restart "$ARG" ;;
    /stop)           cmd_stop "$ARG" ;;
    /start)          cmd_start "$ARG" ;;
    /stopall)        cmd_stopall ;;
    /startall)       cmd_startall ;;
    /clearpenalties) cmd_clearpenalties ;;
    *)               send_message "Unknown command: $CMD — type /help" ;;
  esac
}

# ── MAIN LOOP ────────────────────────────────────────────────
log "NodePulse bot-listener started (SW v2.1.0)"

OFFSET=0
[[ -f "$OFFSET_FILE" ]] && OFFSET=$(cat "$OFFSET_FILE")

while true; do
  RESPONSE=$(get_updates "$OFFSET")

  if [[ -z "$RESPONSE" ]]; then
    sleep 5
    continue
  fi

  UPDATE_COUNT=$(echo "$RESPONSE" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(len(d.get('result', [])))
except:
    print(0)
" 2>/dev/null)

  if [[ "$UPDATE_COUNT" -gt 0 ]]; then
    echo "$RESPONSE" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    for u in d.get('result', []):
        uid  = u.get('update_id', 0)
        msg  = u.get('message', {})
        text = msg.get('text', '')
        cid  = msg.get('chat', {}).get('id', '')
        print(f'{uid}|{cid}|{text}')
except:
    pass
" 2>/dev/null | while IFS='|' read -r UPDATE_ID CHAT_ID TEXT; do
      if [[ "$CHAT_ID" == "$TELEGRAM_CHAT_ID" && "$TEXT" == /* ]]; then
        handle_command "$TEXT"
      fi
      echo $((UPDATE_ID + 1)) > "$OFFSET_FILE"
    done

    [[ -f "$OFFSET_FILE" ]] && OFFSET=$(cat "$OFFSET_FILE")
  fi

  sleep 2
done
