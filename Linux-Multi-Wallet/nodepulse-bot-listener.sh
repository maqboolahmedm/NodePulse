#!/bin/bash

# ============================================================
# DeNet Telegram Bot Listener — Multi Wallet Edition
# v1.2 — RC14 compatible | All fixes applied
# github.com/maqboolahmedm/NodePulse
#
# Fixes in this version:
#   - /stopall requires confirmation: /stopall confirm
#   - /restartall skips paused nodes
#   - paused state shown in /status
#   - /wallets shows license → wallet mapping
# ============================================================

# --- Telegram Config ---
TELEGRAM_BOT_TOKEN="YOUR_TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="YOUR_TELEGRAM_CHAT_ID"

# --- Node Config ---
DENODE_BIN="/usr/bin/denode"

# --- Multi Wallet Map ---
# Format: WALLET_MAP[license]="0xWalletAddress"
declare -A WALLET_MAP
NODEPULSE_WALLET_MAP_ENTRIES

# Derive license list from map keys
LICENSES=($(echo "${!WALLET_MAP[@]}" | tr ' ' '\n' | sort -n))

# --- Paths ---
NODE_LOG_DIR="$HOME/.denode/logs"
RESTART_COUNT_FILE="$HOME/.denode/.restart_counts"
PID_STATE_FILE="$HOME/.denode/.node_pids"
LAST_SEEN_FILE="$HOME/.denode/.node_last_seen"
DOWNTIME_LOG="$HOME/.denode/.node_downtime_log"
PENALTY_FILE="$HOME/.denode/.node_penalties"
CHAIN_STATUS_FILE="$HOME/.denode/.chain_status"
PENALTY_MAX=10
OFFSET_FILE="$HOME/.denode/.bot_offset"
BOT_LOG="$HOME/.denode/bot-listener.log"
GUARD_DIR="$HOME/.nodepulse_guard"
PAUSED_FILE="$GUARD_DIR/paused_nodes"

# --- Timezone Config ---
LOCAL_TIMEZONE="YOUR_TIMEZONE"

# --- Storage Drives ---
STORAGE_DRIVES=(
  "YOUR_STORAGE_PATH/YOUR_LICENSE_1"
  "YOUR_STORAGE_PATH/YOUR_LICENSE_2"
  "YOUR_STORAGE_PATH/YOUR_LICENSE_3"
  "YOUR_STORAGE_PATH/YOUR_LICENSE_4"
  "YOUR_STORAGE_PATH/YOUR_LICENSE_5"
  "YOUR_STORAGE_PATH/YOUR_LICENSE_6"
)

mkdir -p "$NODE_LOG_DIR" "$GUARD_DIR"
touch "$RESTART_COUNT_FILE" "$PID_STATE_FILE" "$LAST_SEEN_FILE" "$DOWNTIME_LOG" "$PENALTY_FILE" "$PAUSED_FILE"

# ============================================================
# Time
# ============================================================
now_utc()   { date -u '+%Y-%m-%d %H:%M:%S UTC'; }
now_local() { TZ="${LOCAL_TIMEZONE}" date '+%H:%M:%S %Z'; }

# ============================================================
# Logging
# ============================================================
log() { echo "[$(now_utc) | $(now_local)] $1" | tee -a "$BOT_LOG"; }

# ============================================================
# Node Helpers
# ============================================================
is_node_running() {
  ps aux | grep -v grep | grep "$DENODE_BIN" | grep -- "--license $1" > /dev/null 2>&1
}

get_node_pid() {
  ps aux | grep -v grep | grep "$DENODE_BIN" | grep -- "--license $1" | awk '{print $2}' | head -n 1
}

is_paused() { grep -qx "$1" "$PAUSED_FILE" 2>/dev/null; }

get_wallet() { echo "${WALLET_MAP[$1]}"; }

get_short_wallet() {
  local W="${WALLET_MAP[$1]}"
  echo "${W:0:6}...${W: -4}"
}

get_node_uptime() {
  local PID; PID=$(get_node_pid "$1")
  [ -z "$PID" ] && echo "not running" && return
  local ET; ET=$(ps -o etime= -p "$PID" 2>/dev/null | tr -d ' ')
  [ -z "$ET" ] && echo "unknown" && return
  local D=0 H=0 M=0
  if echo "$ET" | grep -q '-'; then D=$(echo "$ET"|cut -d'-' -f1); ET=$(echo "$ET"|cut -d'-' -f2); fi
  local P; IFS=':' read -ra P <<< "$ET"
  case ${#P[@]} in 3) H=${P[0]}; M=${P[1]} ;; 2) M=${P[0]} ;; esac
  D=$((10#$D)); H=$((10#$H)); M=$((10#$M))
  local R=""
  [ "$D" -gt 0 ] && R="${D}d "; [ "$H" -gt 0 ] && R="${R}${H}h "; [ "$M" -gt 0 ] && R="${R}${M}m"
  [ -z "$R" ] && R="< 1m"; echo "$R"
}

# ============================================================
# Counters
# ============================================================
get_restart_count() {
  local C; C=$(grep "^${1}=" "$RESTART_COUNT_FILE" 2>/dev/null | cut -d= -f2)
  echo "${C:-0}"
}

get_penalty_count() {
  local V; V=$(grep "^${1}=" "$PENALTY_FILE" 2>/dev/null | cut -d= -f2)
  echo "${V:-0}"
}

increment_restart_count() {
  local N=$(( $(get_restart_count "$1") + 1 ))
  sed -i "/^${1}=/d" "$RESTART_COUNT_FILE" 2>/dev/null
  echo "${1}=${N}" >> "$RESTART_COUNT_FILE"
}

reset_restart_counts() { > "$RESTART_COUNT_FILE"; log "Restart counts reset."; }

# ============================================================
# PID / Downtime
# ============================================================
get_saved_pid() { local V; V=$(grep "^${1}=" "$PID_STATE_FILE" 2>/dev/null | cut -d= -f2); echo "${V:-}"; }
get_last_seen() { local V; V=$(grep "^${1}=" "$LAST_SEEN_FILE" 2>/dev/null | cut -d= -f2); echo "${V:-}"; }

format_duration() {
  local D=$(($1/86400)) H=$((($1%86400)/3600)) M=$((($1%3600)/60))
  local R=""; [ "$D" -gt 0 ] && R="${D}d "; [ "$H" -gt 0 ] && R="${R}${H}h "; R="${R}${M}m"; echo "$R"
}

get_pid_change_info() {
  local CUR; CUR=$(get_node_pid "$1")
  local SAV; SAV=$(get_saved_pid "$1")
  if [ -n "$SAV" ] && [ -n "$CUR" ] && [ "$SAV" != "$CUR" ]; then
    local LS; LS=$(get_last_seen "$1")
    local NOW=$(date +%s) OD="unknown" WD="unknown"
    if [ -n "$LS" ]; then
      OD=$(format_duration $(( NOW - LS )))
      WD=$(date -u -d "@${LS}" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || date -u -r "$LS" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null)
    fi
    echo "CHANGED|${SAV}|${CUR}|${WD}|${OD}"
  else
    echo "SAME"
  fi
}

get_last_downtime() {
  local LICENSE="$1"
  [ ! -f "$DOWNTIME_LOG" ] && echo "No history yet." && return
  local LAST; LAST=$(grep "^${LICENSE}|" "$DOWNTIME_LOG" 2>/dev/null | tail -1)
  [ -z "$LAST" ] && echo "No recorded downtime." && return
  local RA WD D OP NP
  RA=$(echo "$LAST"|cut -d'|' -f2); WD=$(echo "$LAST"|cut -d'|' -f3)
  D=$(echo "$LAST"|cut -d'|' -f4); OP=$(echo "$LAST"|cut -d'|' -f5); NP=$(echo "$LAST"|cut -d'|' -f6)
  echo "📅 Last down: ${WD}
⏱ Offline: ${D}
🔄 Restarted: ${RA}
🆔 PID: ${OP}→${NP}"
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
  local CHAT_ID="$1" LINES="" RALERT="" HAS=0
  for LICENSE in "${LICENSES[@]}"; do
    local SW; SW=$(get_short_wallet "$LICENSE")
    if is_node_running "$LICENSE"; then
      local PID UP RC PI
      PID=$(get_node_pid "$LICENSE"); UP=$(get_node_uptime "$LICENSE")
      RC=$(get_restart_count "$LICENSE"); PI=$(get_pid_change_info "$LICENSE")
      local PT=""; is_paused "$LICENSE" && PT=" 🛑PAUSED"
      if [ "$PI" != "SAME" ]; then
        local OLD WD OD
        OLD=$(echo "$PI"|cut -d'|' -f2); WD=$(echo "$PI"|cut -d'|' -f4); OD=$(echo "$PI"|cut -d'|' -f5)
        LINES="${LINES}⚠️ <code>${LICENSE}</code> [${SW}] — PID <code>${PID}</code> — Up: <b>${UP}</b> — R: <b>${RC}</b>${PT}\n"
        RALERT="${RALERT}⚠️ <code>${LICENSE}</code> restarted silently!\n"
        RALERT="${RALERT}   🔴 Old: <code>${OLD}</code> → 🟢 New: <code>${PID}</code>\n"
        RALERT="${RALERT}   📅 Last alive: <b>${WD}</b> | ⏱ Offline: <b>${OD}</b>\n"
        HAS=1
      else
        LINES="${LINES}🟢 <code>${LICENSE}</code> [${SW}] — PID <code>${PID}</code> — Up: <b>${UP}</b> — R: <b>${RC}</b>${PT}\n"
      fi
    else
      local RC; RC=$(get_restart_count "$LICENSE")
      local PT=""; is_paused "$LICENSE" && PT=" 🛑PAUSED"
      local LS; LS=$(get_last_seen "$LICENSE")
      if [ -n "$LS" ]; then
        local LSS; LSS=$(date -u -d "@${LS}" '+%H:%M UTC' 2>/dev/null || date -u -r "$LS" '+%H:%M UTC' 2>/dev/null)
        LINES="${LINES}🔴 <code>${LICENSE}</code> [${SW}] — <b>DOWN</b> — Last: ${LSS} — R: <b>${RC}</b>${PT}\n"
      else
        LINES="${LINES}🔴 <code>${LICENSE}</code> [${SW}] — <b>DOWN</b> — R: <b>${RC}</b>${PT}\n"
      fi
    fi
  done
  local AB=""
  [ "$HAS" -eq 1 ] && AB="
⚠️ <b>Silent Restarts:</b>
$(echo -e "$RALERT")"
  send_message "$CHAT_ID" "📊 <b>DeNet Node Status</b> <i>(Multi-Wallet)</i>
🕐 $(now_utc) | $(now_local)
📍 Host: $(hostname)
${AB}
<b>Node Status:</b>
$(echo -e "$LINES")"
}

cmd_wallets() {
  local CHAT_ID="$1" MSG="<b>🔑 License → Wallet Mapping</b>\n\n"
  for LICENSE in "${LICENSES[@]}"; do
    local W; W=$(get_wallet "$LICENSE")
    MSG+="<b>${LICENSE}</b>: <code>${W:0:6}...${W: -4}</code>\n"
  done
  send_message "$CHAT_ID" "$MSG"
}

cmd_restarts() {
  local CHAT_ID="$1" LINES=""
  for LICENSE in "${LICENSES[@]}"; do
    local C; C=$(get_restart_count "$LICENSE")
    local I="🟢"; [ "$C" -gt 0 ] && I="🔄"; [ "$C" -ge 5 ] && I="🔴"
    LINES="${LINES}${I} <code>${LICENSE}</code> — <b>${C}</b> restart(s)\n"
  done
  send_message "$CHAT_ID" "🔄 <b>Restart Counts</b>
$(echo -e "$LINES")
<i>Use /resetcounts to reset</i>"
}

cmd_restart_node() {
  local CHAT_ID="$1" LICENSE="$2"
  local VALID=0
  for L in "${LICENSES[@]}"; do [ "$L" = "$LICENSE" ] && VALID=1 && break; done
  if [ "$VALID" -eq 0 ]; then
    send_message "$CHAT_ID" "❌ Unknown license: <code>${LICENSE}</code>"; return
  fi
  if is_paused "$LICENSE"; then
    send_message "$CHAT_ID" "⏸️ Node <code>${LICENSE}</code> is PAUSED. Use /start ${LICENSE} first."; return
  fi
  local WALLET; WALLET=$(get_wallet "$LICENSE")
  send_message "$CHAT_ID" "🔄 <b>Restarting Node ${LICENSE}...</b>"
  local OLD; OLD=$(get_node_pid "$LICENSE")
  [ -n "$OLD" ] && kill "$OLD" 2>/dev/null && sleep 2
  nohup "$DENODE_BIN" --address "$WALLET" --license "$LICENSE" \
    >> "$NODE_LOG_DIR/node-${LICENSE}.log" 2>&1 &
  sleep 4
  if is_node_running "$LICENSE"; then
    local NEW; NEW=$(get_node_pid "$LICENSE")
    increment_restart_count "$LICENSE"
    local T; T=$(get_restart_count "$LICENSE")
    send_message "$CHAT_ID" "✅ <b>Node ${LICENSE} Restarted</b>
🆔 New PID: <code>${NEW}</code> | 🔄 Total: <b>${T}</b>
🕐 $(now_utc) | $(now_local)"
  else
    send_message "$CHAT_ID" "❌ <b>Node ${LICENSE} Failed to Restart</b>
⚠️ Manual intervention required."
  fi
}

cmd_restart_all() {
  local CHAT_ID="$1"
  send_message "$CHAT_ID" "🔄 <b>Restarting All Nodes...</b>"
  local S=0 F=0
  for LICENSE in "${LICENSES[@]}"; do
    if is_paused "$LICENSE"; then log "Skipping $LICENSE — paused"; continue; fi
    local WALLET; WALLET=$(get_wallet "$LICENSE")
    local OLD; OLD=$(get_node_pid "$LICENSE")
    [ -n "$OLD" ] && kill "$OLD" 2>/dev/null && sleep 1
    nohup "$DENODE_BIN" --address "$WALLET" --license "$LICENSE" \
      >> "$NODE_LOG_DIR/node-${LICENSE}.log" 2>&1 &
    sleep 4
    if is_node_running "$LICENSE"; then increment_restart_count "$LICENSE"; S=$(( S+1 ))
    else F=$(( F+1 )); fi
  done
  local LINES=""
  for LICENSE in "${LICENSES[@]}"; do
    local SW; SW=$(get_short_wallet "$LICENSE")
    if is_paused "$LICENSE"; then LINES="${LINES}⏸️ <code>${LICENSE}</code> — PAUSED\n"
    elif is_node_running "$LICENSE"; then
      LINES="${LINES}✅ <code>${LICENSE}</code> [${SW}] — PID <code>$(get_node_pid $LICENSE)</code>\n"
    else LINES="${LINES}❌ <code>${LICENSE}</code> [${SW}] — FAILED\n"; fi
  done
  send_message "$CHAT_ID" "$([ "$F" -eq 0 ] && echo "✅" || echo "⚠️") <b>Restart All Complete</b>
✅ Success: <b>${S}</b> | ❌ Failed: <b>${F}</b>
$(echo -e "$LINES")"
}

cmd_reset_counts() {
  reset_restart_counts
  send_message "$1" "✅ <b>All restart counts reset to 0</b>"
}

cmd_disk() {
  local CHAT_ID="$1" LINES=""
  for DRIVE in "${STORAGE_DRIVES[@]}"; do
    if [ ! -d "$DRIVE" ]; then LINES="${LINES}❌ $(basename $DRIVE) — NOT MOUNTED\n"; continue; fi
    local U UD T F
    U=$(df "$DRIVE" | awk 'NR==2 {gsub("%",""); print $5}')
    UD=$(df -h "$DRIVE" | awk 'NR==2 {print $3}')
    T=$(df -h "$DRIVE" | awk 'NR==2 {print $2}')
    F=$(df -h "$DRIVE" | awk 'NR==2 {print $4}')
    local I="🟢"; [ "$U" -ge 85 ] && I="🔴"; [ "$U" -ge 70 ] && [ "$U" -lt 85 ] && I="🟡"
    LINES="${LINES}${I} <code>$(basename $DRIVE)</code>: ${U}% — ${UD}/${T} (free: ${F})\n"
  done
  send_message "$CHAT_ID" "💾 <b>Disk Usage</b>
🕐 $(now_utc)
$(echo -e "$LINES")"
}

cmd_version() {
  local VER; VER=$("$DENODE_BIN" --version 2>/dev/null | head -1 || echo "unknown")
  send_message "$1" "📦 <b>DeNet Version</b>: <code>${VER}</code>
📍 Host: $(hostname)"
}

cmd_history() {
  local CHAT_ID="$1" LINES=""
  for LICENSE in "${LICENSES[@]}"; do
    local SW; SW=$(get_short_wallet "$LICENSE")
    local I; I=$(get_last_downtime "$LICENSE")
    local R; R=$(get_restart_count "$LICENSE")
    LINES="${LINES}🔑 <code>${LICENSE}</code> [${SW}] — R: <b>${R}</b>\n   └ ${I}\n"
  done
  send_message "$CHAT_ID" "📋 <b>Downtime History</b>
$(echo -e "$LINES")"
}

cmd_penalties() {
  local CHAT_ID="$1" LINES="" HAS=0
  for LICENSE in "${LICENSES[@]}"; do
    local SW; SW=$(get_short_wallet "$LICENSE")
    local C; C=$(get_penalty_count "$LICENSE")
    local I SM
    if   [ "$C" -eq 0 ];  then I="🟢"; SM="Clean"
    elif [ "$C" -lt 5 ];  then I="🟡"; SM="Watch"
    elif [ "$C" -lt 8 ];  then I="🟠"; SM="Warning — $(( PENALTY_MAX - C )) cycles left"; HAS=1
    elif [ "$C" -lt 10 ]; then I="🔴"; SM="CRITICAL — $(( PENALTY_MAX - C )) cycle(s) left"; HAS=1
    else                       I="🚫"; SM="Threshold reached"; HAS=1
    fi
    LINES="${LINES}${I} <code>${LICENSE}</code> [${SW}] — <b>${C}/${PENALTY_MAX}</b> — ${SM}\n"
  done
  local FOOT=""
  [ "$HAS" -eq 1 ] && FOOT="\n⚠️ <i>Penalties reset after successful proof | Pool removal = 15h inactivity</i>"
  send_message "$CHAT_ID" "📊 <b>Penalty Status</b>
🕐 $(now_utc)
$(echo -e "$LINES")
<b>Scale:</b> 0=Clean · 5=Watch · 8=Critical · 10=Threshold${FOOT}"
}

cmd_chain() {
  local CHAT_ID="$1"
  if [ ! -f "$CHAIN_STATUS_FILE" ]; then
    send_message "$CHAT_ID" "⛓ No chain data yet — wait for next monitor run (~5 min)"; return
  fi
  local LINES; LINES=$(python3 - "$CHAIN_STATUS_FILE" <<'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as f: data=json.load(f)
    nodes=data.get('nodes',{}); fetched=data.get('fetched_at','unknown'); lines=[]
    for lic,info in nodes.items():
        s=info.get('status','unknown').upper(); age=info.get('age','unknown')
        pool=info.get('pool',''); stage=info.get('stage',''); err=info.get('last_error','')
        icon='🟢' if s=='ONLINE' else ('🟡' if s=='PENDING' else ('🔴' if s=='OFFLINE' else '⚪'))
        ps=f' | Pool: {pool}' if pool else ''; ss=f' | {stage}' if stage else ''
        es=f'\n   ⚠️ {err[:80]}' if err and s!='ONLINE' else ''
        lines.append(f'{icon} <code>{lic}</code> — <b>{s}</b>{ps}{ss}\n   📅 Last proof: {age}{es}')
    print('\n'.join(lines)); print(f'FETCHED:{fetched}')
except Exception as e: print(f'ERROR:{e}')
PYEOF
)
  local FETCHED; FETCHED=$(echo "$LINES" | grep "^FETCHED:" | cut -d: -f2-)
  LINES=$(echo "$LINES" | grep -v "^FETCHED:\|^ERROR:")
  send_message "$CHAT_ID" "⛓ <b>On-Chain Status</b>
🕐 $(now_utc) | $(now_local)
🔄 Updated: ${FETCHED}

${LINES}

<i>ONLINE=proof<95min | PENDING=95-190min | OFFLINE=>190min</i>"
}

cmd_stop_node() {
  local CHAT_ID="$1" LICENSE="$2"
  local VALID=0
  for L in "${LICENSES[@]}"; do [ "$L" = "$LICENSE" ] && VALID=1 && break; done
  if [ "$VALID" -eq 0 ]; then send_message "$CHAT_ID" "❌ Unknown license: <code>${LICENSE}</code>"; return; fi
  if is_paused "$LICENSE"; then send_message "$CHAT_ID" "ℹ️ Node <code>${LICENSE}</code> is already paused."; return; fi
  echo "$LICENSE" >> "$PAUSED_FILE"
  local PID; PID=$(get_node_pid "$LICENSE")
  if [ -n "$PID" ]; then
    kill "$PID" 2>/dev/null; sleep 1
    send_message "$CHAT_ID" "🛑 <b>Node ${LICENSE} Stopped</b>
🆔 Killed PID: <code>${PID}</code>
⚠️ Monitor and guard will not restart it.
Use /start ${LICENSE} to resume."
  else
    send_message "$CHAT_ID" "🛑 Node <code>${LICENSE}</code> marked PAUSED (was not running)."
  fi
}

cmd_start_node() {
  local CHAT_ID="$1" LICENSE="$2"
  local VALID=0
  for L in "${LICENSES[@]}"; do [ "$L" = "$LICENSE" ] && VALID=1 && break; done
  if [ "$VALID" -eq 0 ]; then send_message "$CHAT_ID" "❌ Unknown license: <code>${LICENSE}</code>"; return; fi
  sed -i "/^${LICENSE}$/d" "$PAUSED_FILE" 2>/dev/null
  if is_node_running "$LICENSE"; then
    send_message "$CHAT_ID" "⚠️ Node <code>${LICENSE}</code> unpaused — already running"; return
  fi
  local WALLET; WALLET=$(get_wallet "$LICENSE")
  send_message "$CHAT_ID" "▶️ <b>Starting Node ${LICENSE}...</b>"
  nohup "$DENODE_BIN" --address "$WALLET" --license "$LICENSE" \
    >> "$NODE_LOG_DIR/node-${LICENSE}.log" 2>&1 &
  sleep 4
  if is_node_running "$LICENSE"; then
    send_message "$CHAT_ID" "✅ <b>Node ${LICENSE} Started</b>
🆔 PID: <code>$(get_node_pid "$LICENSE")</code>
ℹ️ Monitoring resumed."
  else
    send_message "$CHAT_ID" "❌ <b>Node ${LICENSE} Failed to Start</b>"
  fi
}

cmd_stop_all() {
  local CHAT_ID="$1" CONFIRMED="$2"
  # FIX: require confirmation to prevent accidental stopall
  if [ "$CONFIRMED" != "confirm" ]; then
    send_message "$CHAT_ID" "⚠️ <b>Confirmation Required</b>
This will stop ALL nodes.
To confirm, send: <code>/stopall confirm</code>"
    return
  fi
  send_message "$CHAT_ID" "🛑 <b>Stopping ALL nodes...</b>"
  local COUNT=0
  for LICENSE in "${LICENSES[@]}"; do
    echo "$LICENSE" >> "$PAUSED_FILE"
    local PID; PID=$(get_node_pid "$LICENSE")
    if [ -n "$PID" ]; then kill "$PID" 2>/dev/null; COUNT=$(( COUNT+1 )); fi
  done
  sort -u "$PAUSED_FILE" -o "$PAUSED_FILE"
  send_message "$CHAT_ID" "🛑 <b>All Nodes Stopped</b>
🔢 Killed: <b>${COUNT}</b> running nodes
⚠️ Monitor and guard will not restart any node.
Use /startall or /start &lt;license&gt; to resume."
}

cmd_start_all() {
  local CHAT_ID="$1"
  send_message "$CHAT_ID" "▶️ <b>Starting ALL nodes...</b>"
  > "$PAUSED_FILE"
  local COUNT=0
  for LICENSE in "${LICENSES[@]}"; do
    if ! is_node_running "$LICENSE"; then
      local WALLET; WALLET=$(get_wallet "$LICENSE")
      nohup "$DENODE_BIN" --address "$WALLET" --license "$LICENSE" \
        >> "$NODE_LOG_DIR/node-${LICENSE}.log" 2>&1 &
      COUNT=$(( COUNT+1 )); sleep 1
    fi
  done
  sleep 4
  local LINES="" FAILED=0
  for LICENSE in "${LICENSES[@]}"; do
    local SW; SW=$(get_short_wallet "$LICENSE")
    if is_node_running "$LICENSE"; then
      LINES="${LINES}✅ <code>${LICENSE}</code> [${SW}] — PID <code>$(get_node_pid "$LICENSE")</code>\n"
    else
      LINES="${LINES}❌ <code>${LICENSE}</code> [${SW}] — FAILED\n"; FAILED=$(( FAILED+1 ))
    fi
  done
  send_message "$CHAT_ID" "$([ "$FAILED" -eq 0 ] && echo "✅" || echo "⚠️") <b>Start All Complete</b>
$(echo -e "$LINES")
<i>Use /status to verify.</i>"
}

cmd_help() {
  local CHAT_ID="$1"
  send_message "$CHAT_ID" "🤖 <b>DeNet Node Monitor Bot</b> <i>(Multi-Wallet)</i>
📍 Host: $(hostname)

🔄 <b>Restart:</b>
/restart &lt;license&gt; — Restart specific node
/restartall — Restart all nodes

🛑 <b>Stop / Start:</b>
/stop &lt;license&gt; — Stop + prevent auto-restart
/start &lt;license&gt; — Unpause and start
/stopall confirm — Stop ALL nodes (requires confirm)
/startall — Start all nodes

📊 <b>Status:</b>
/status — Live node status
/wallets — License → wallet mapping
/chain — On-chain proof status
/penalties — Penalty count per node
/restarts — Restart count per node
/history — Last downtime per node
/disk — Storage usage
/version — DeNet binary version

🔧 <b>Utility:</b>
/resetcounts — Reset restart counters
/help — This message"
}

# ============================================================
# Main Loop
# ============================================================
log "=========================================="
log "  DeNet Bot Listener Started (MW v1.2)"
log "  Host: $(hostname)"
log "=========================================="

send_message "$TELEGRAM_CHAT_ID" "🤖 <b>DeNet Node Monitor Bot Started</b> <i>(Multi-Wallet)</i>
📍 Host: $(hostname)
🕐 $(now_utc) | $(now_local)
Send /help for commands."

BOT_TRIGGER_FILE="$HOME/.denode/.bot_trigger"
OFFSET=0
[ -f "$OFFSET_FILE" ] && OFFSET=$(cat "$OFFSET_FILE")

while true; do

  if [ -f "$BOT_TRIGGER_FILE" ]; then
    TRIGGER_CMD=$(cat "$BOT_TRIGGER_FILE"); rm -f "$BOT_TRIGGER_FILE"
    if [ -n "$TRIGGER_CMD" ]; then
      log "Web trigger: $TRIGGER_CMD"
      TL="${TRIGGER_CMD,,}"
      case "$TL" in
        /status|/s)        cmd_status      "$TELEGRAM_CHAT_ID" ;;
        /wallets)          cmd_wallets     "$TELEGRAM_CHAT_ID" ;;
        /chain|/txn)       cmd_chain       "$TELEGRAM_CHAT_ID" ;;
        /restarts|/rc)     cmd_restarts    "$TELEGRAM_CHAT_ID" ;;
        /penalties|/pen)   cmd_penalties   "$TELEGRAM_CHAT_ID" ;;
        /restartall)       cmd_restart_all "$TELEGRAM_CHAT_ID" ;;
        /resetcounts)      cmd_reset_counts "$TELEGRAM_CHAT_ID" ;;
        /disk)             cmd_disk        "$TELEGRAM_CHAT_ID" ;;
        /history|/h)       cmd_history     "$TELEGRAM_CHAT_ID" ;;
        /version)          cmd_version     "$TELEGRAM_CHAT_ID" ;;
        /help)             cmd_help        "$TELEGRAM_CHAT_ID" ;;
        /stopall\ confirm) cmd_stop_all    "$TELEGRAM_CHAT_ID" "confirm" ;;
        /stopall)          cmd_stop_all    "$TELEGRAM_CHAT_ID" "" ;;
        /startall)         cmd_start_all   "$TELEGRAM_CHAT_ID" ;;
        /stop\ *)          cmd_stop_node   "$TELEGRAM_CHAT_ID" "$(echo "$TRIGGER_CMD"|awk '{print $2}')" ;;
        /start\ *)         cmd_start_node  "$TELEGRAM_CHAT_ID" "$(echo "$TRIGGER_CMD"|awk '{print $2}')" ;;
        /restart\ *)       cmd_restart_node "$TELEGRAM_CHAT_ID" "$(echo "$TRIGGER_CMD"|awk '{print $2}')" ;;
      esac
    fi
  fi

  UPDATES=$(get_updates "$OFFSET")

  if ! echo "$UPDATES" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('ok') else 1)" 2>/dev/null; then
    log "⚠️ Telegram API error — retrying in 5s..."
    sleep 5; continue
  fi

  RESULT=$(echo "$UPDATES" | python3 -c "
import json, sys
data=json.load(sys.stdin)
for u in data.get('result',[]):
    uid=u.get('update_id',0)
    msg=u.get('message',{})
    cid=str(msg.get('chat',{}).get('id',''))
    text=msg.get('text','').strip()
    print(f'{uid}|{cid}|{text}')
" 2>/dev/null)

  while IFS='|' read -r UPDATE_ID CHAT_ID TEXT; do
    [ -z "$UPDATE_ID" ] && continue
    NEXT=$(( UPDATE_ID + 1 ))
    [ "$NEXT" -gt "$OFFSET" ] && OFFSET="$NEXT"
    if [ "$CHAT_ID" != "$TELEGRAM_CHAT_ID" ]; then
      log "Ignored: unauthorized chat $CHAT_ID"; continue
    fi
    TL="${TEXT,,}"
    log "CMD: $TEXT"
    case "$TL" in
      /status|/s)                    cmd_status       "$CHAT_ID" ;;
      /wallets)                      cmd_wallets      "$CHAT_ID" ;;
      /chain|/blockchain|/txn)       cmd_chain        "$CHAT_ID" ;;
      /restarts|/restart_counts|/rc) cmd_restarts     "$CHAT_ID" ;;
      /penalties|/penalty|/pen)      cmd_penalties    "$CHAT_ID" ;;
      /restartall|/restart_all)      cmd_restart_all  "$CHAT_ID" ;;
      /resetcounts|/reset_counts)    cmd_reset_counts "$CHAT_ID" ;;
      /disk|/storage)                cmd_disk         "$CHAT_ID" ;;
      /history|/h)                   cmd_history      "$CHAT_ID" ;;
      /version|/ver)                 cmd_version      "$CHAT_ID" ;;
      /stopall\ confirm)             cmd_stop_all     "$CHAT_ID" "confirm" ;;
      /stopall)                      cmd_stop_all     "$CHAT_ID" "" ;;
      /startall)                     cmd_start_all    "$CHAT_ID" ;;
      /help)                         cmd_help         "$CHAT_ID" ;;
      /stop\ *)
        L=$(echo "$TEXT"|awk '{print $2}'); cmd_stop_node    "$CHAT_ID" "$L" ;;
      /start\ *)
        L=$(echo "$TEXT"|awk '{print $2}'); cmd_start_node   "$CHAT_ID" "$L" ;;
      /restart\ *)
        L=$(echo "$TEXT"|awk '{print $2}'); cmd_restart_node "$CHAT_ID" "$L" ;;
      *)
        if echo "$TEXT" | grep -q '^/'; then
          send_message "$CHAT_ID" "❓ Unknown command: <code>${TEXT}</code> — /help"
        fi ;;
    esac
  done <<< "$RESULT"

  echo "$OFFSET" > "$OFFSET_FILE"
done
