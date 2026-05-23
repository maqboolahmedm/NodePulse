#!/bin/bash

# ============================================================
# NodePulse Monitor & Auto-Restart Script
# Linux Multi-Wallet Version
# v2.2 — RC14 compatible | All fixes applied
# github.com/maqboolahmedm/NodePulse
#
# Fixes in this version:
#   - single instance lock
#   - DENODE_PASSWORD check per wallet at startup
#   - storage mount check before every restart
#   - tunnel check uses license-*.log first
#   - proof string updated to "Successfully submitted proof"
#   - context deadline exceeded removed from ERROR_PATTERNS
#   - penalty restart disabled (alert only)
#   - watchdog: restart loop detection
# ============================================================

# ============================================================
# WALLET CONFIG
# ============================================================

# --- Wallet 1 ---
WALLET_1_ADDRESS="YOUR_WALLET_1_ADDRESS"
WALLET_1_PASSWORD="YOUR_WALLET_1_PASSWORD"
WALLET_1_LICENSES=(YOUR_W1_LICENSE_1 YOUR_W1_LICENSE_2 YOUR_W1_LICENSE_3)

# --- Wallet 2 ---
WALLET_2_ADDRESS="YOUR_WALLET_2_ADDRESS"
WALLET_2_PASSWORD="YOUR_WALLET_2_PASSWORD"
WALLET_2_LICENSES=(YOUR_W2_LICENSE_1 YOUR_W2_LICENSE_2 YOUR_W2_LICENSE_3)

# --- Wallet 3 (optional) ---
WALLET_3_ADDRESS=""
WALLET_3_PASSWORD=""
WALLET_3_LICENSES=()

# --- Wallet 4 (optional) ---
WALLET_4_ADDRESS=""
WALLET_4_PASSWORD=""
WALLET_4_LICENSES=()

# ============================================================
# Per-License Config
# ============================================================

declare -A NODE_WALLET
declare -A NODE_PORT
declare -A NODE_STORAGE
declare -A NODE_RPC

# Wallet 1 nodes
NODE_WALLET[YOUR_W1_LICENSE_1]="$WALLET_1_ADDRESS"
NODE_PORT[YOUR_W1_LICENSE_1]=YOUR_W1_PORT_1
NODE_STORAGE[YOUR_W1_LICENSE_1]="YOUR_STORAGE_PATH/YOUR_W1_LICENSE_1"
NODE_RPC[YOUR_W1_LICENSE_1]="https://peaq.api.onfinality.io/rpc?apikey=YOUR_W1_RPC_APIKEY_1"

NODE_WALLET[YOUR_W1_LICENSE_2]="$WALLET_1_ADDRESS"
NODE_PORT[YOUR_W1_LICENSE_2]=YOUR_W1_PORT_2
NODE_STORAGE[YOUR_W1_LICENSE_2]="YOUR_STORAGE_PATH/YOUR_W1_LICENSE_2"
NODE_RPC[YOUR_W1_LICENSE_2]="https://peaq.api.onfinality.io/rpc?apikey=YOUR_W1_RPC_APIKEY_2"

NODE_WALLET[YOUR_W1_LICENSE_3]="$WALLET_1_ADDRESS"
NODE_PORT[YOUR_W1_LICENSE_3]=YOUR_W1_PORT_3
NODE_STORAGE[YOUR_W1_LICENSE_3]="YOUR_STORAGE_PATH/YOUR_W1_LICENSE_3"
NODE_RPC[YOUR_W1_LICENSE_3]="https://peaq.api.onfinality.io/rpc?apikey=YOUR_W1_RPC_APIKEY_3"

# Wallet 2 nodes
NODE_WALLET[YOUR_W2_LICENSE_1]="$WALLET_2_ADDRESS"
NODE_PORT[YOUR_W2_LICENSE_1]=YOUR_W2_PORT_1
NODE_STORAGE[YOUR_W2_LICENSE_1]="YOUR_STORAGE_PATH/YOUR_W2_LICENSE_1"
NODE_RPC[YOUR_W2_LICENSE_1]="https://peaq.api.onfinality.io/rpc?apikey=YOUR_W2_RPC_APIKEY_1"

NODE_WALLET[YOUR_W2_LICENSE_2]="$WALLET_2_ADDRESS"
NODE_PORT[YOUR_W2_LICENSE_2]=YOUR_W2_PORT_2
NODE_STORAGE[YOUR_W2_LICENSE_2]="YOUR_STORAGE_PATH/YOUR_W2_LICENSE_2"
NODE_RPC[YOUR_W2_LICENSE_2]="https://peaq.api.onfinality.io/rpc?apikey=YOUR_W2_RPC_APIKEY_2"

NODE_WALLET[YOUR_W2_LICENSE_3]="$WALLET_2_ADDRESS"
NODE_PORT[YOUR_W2_LICENSE_3]=YOUR_W2_PORT_3
NODE_STORAGE[YOUR_W2_LICENSE_3]="YOUR_STORAGE_PATH/YOUR_W2_LICENSE_3"
NODE_RPC[YOUR_W2_LICENSE_3]="https://peaq.api.onfinality.io/rpc?apikey=YOUR_W2_RPC_APIKEY_3"

# ============================================================
TELEGRAM_BOT_TOKEN="YOUR_TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="YOUR_TELEGRAM_CHAT_ID"
DENODE_BIN="/usr/bin/denode"
LOCAL_TIMEZONE="YOUR_TIMEZONE"
DUCKDNS_TOKEN="YOUR_DUCKDNS_TOKEN"
DUCKDNS_DOMAIN="YOUR_DUCKDNS_DOMAIN"
DISK_ALERT_THRESHOLD=85
DAILY_SUMMARY_HOUR=8
PENALTY_WARN=5
PENALTY_CRITICAL=8
PENALTY_MAX=10
CYCLE_MINUTES=90
TUNNEL_SILENCE_THRESHOLD=6000

# ============================================================
# Paths
# ============================================================
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

mkdir -p "$NODE_LOG_DIR" "$GUARD_DIR" "$(dirname $STATUS_JSON)" 2>/dev/null || true
touch "$PID_STATE_FILE" "$LAST_SEEN_FILE" "$DOWNTIME_LOG" "$PENALTY_FILE" "$PAUSED_FILE"

# ── Single instance lock ─────────────────────────────────────
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] Already running — skipping" >> "$LOG_FILE"
  exit 0
fi
trap "rm -f $LOCK_FILE" EXIT
# ─────────────────────────────────────────────────────────────

# ============================================================
# Build combined license list
# ============================================================
ALL_LICENSES=()
[ ${#WALLET_1_LICENSES[@]} -gt 0 ] && ALL_LICENSES+=("${WALLET_1_LICENSES[@]}")
[ ${#WALLET_2_LICENSES[@]} -gt 0 ] && ALL_LICENSES+=("${WALLET_2_LICENSES[@]}")
[ ${#WALLET_3_LICENSES[@]} -gt 0 ] && ALL_LICENSES+=("${WALLET_3_LICENSES[@]}")
[ ${#WALLET_4_LICENSES[@]} -gt 0 ] && ALL_LICENSES+=("${WALLET_4_LICENSES[@]}")

get_wallet_password() {
  local WALLET="${NODE_WALLET[$1]}"
  if   [ "$WALLET" = "$WALLET_1_ADDRESS" ]; then echo "$WALLET_1_PASSWORD"
  elif [ "$WALLET" = "$WALLET_2_ADDRESS" ]; then echo "$WALLET_2_PASSWORD"
  elif [ "$WALLET" = "$WALLET_3_ADDRESS" ]; then echo "$WALLET_3_PASSWORD"
  elif [ "$WALLET" = "$WALLET_4_ADDRESS" ]; then echo "$WALLET_4_PASSWORD"
  fi
}

get_wallet_label() {
  local WALLET="${NODE_WALLET[$1]}"
  if   [ "$WALLET" = "$WALLET_1_ADDRESS" ]; then echo "W1"
  elif [ "$WALLET" = "$WALLET_2_ADDRESS" ]; then echo "W2"
  elif [ "$WALLET" = "$WALLET_3_ADDRESS" ]; then echo "W3"
  elif [ "$WALLET" = "$WALLET_4_ADDRESS" ]; then echo "W4"
  else echo "??"
  fi
}

# ============================================================
# Time / Log
# ============================================================
now_utc()   { date -u '+%Y-%m-%d %H:%M:%S UTC'; }
now_local() { TZ="${LOCAL_TIMEZONE}" date '+%H:%M:%S %Z'; }
log()       { echo "[$(now_utc) | $(now_local)] $1" | tee -a "$LOG_FILE"; }

send_telegram() {
  curl -s --max-time 15 -X POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" -d text="${1}" \
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

is_paused() {
  grep -qx "$1" "$PAUSED_FILE" 2>/dev/null
}

# ============================================================
# Storage mount check
# ============================================================
check_storage_mounted() {
  local LICENSE="$1"
  local DRIVE="${NODE_STORAGE[$LICENSE]}"
  local WL=$(get_wallet_label "$LICENSE")
  if [ -z "$DRIVE" ]; then
    log "⚠️ No storage path for node $LICENSE"
    return 1
  fi
  if [ ! -d "$DRIVE" ] || ! df "$DRIVE" > /dev/null 2>&1; then
    log "🔴 Storage not mounted for node $LICENSE [$WL]: $DRIVE"
    send_telegram "🔴 <b>Storage Not Mounted</b>
🔑 License: <code>${LICENSE}</code> [<b>${WL}</b>]
💾 Path: <code>${DRIVE}</code>
⚠️ Node will NOT be restarted until storage is mounted
🕐 $(now_utc) | $(now_local)"
    return 1
  fi
  return 0
}

# ============================================================
# Tunnel Health Check — license-*.log first
# ============================================================
check_tunnel_health() {
  local LICENSE="$1"
  local PORT="${NODE_PORT[$LICENSE]}"
  local LOG_A="$NODE_LOG_DIR/license-${LICENSE}.log"
  local LOG_B="$NODE_LOG_DIR/node-${LICENSE}.log"
  local LOG="${LOG_A}"; [ ! -f "$LOG" ] && LOG="$LOG_B"
  local PORT_OPEN=0 LOG_FRESH=0
  if [ -n "$PORT" ] && ss -tlnp 2>/dev/null | grep -q ":${PORT}"; then PORT_OPEN=1; fi
  if [ -f "$LOG" ]; then
    local AGE=$(( $(date +%s) - $(stat -c %Y "$LOG" 2>/dev/null || echo 0) ))
    [ "$AGE" -lt "$TUNNEL_SILENCE_THRESHOLD" ] && LOG_FRESH=1
  fi
  if [ "$PORT_OPEN" -eq 0 ] && [ "$LOG_FRESH" -eq 0 ]; then echo "DEAD"
  elif [ "$PORT_OPEN" -eq 0 ]; then echo "NO_PORT"
  elif [ "$LOG_FRESH" -eq 0 ]; then echo "SILENT"
  else echo "OK"
  fi
}

get_node_uptime() {
  local PID=$(get_node_pid "$1")
  [ -z "$PID" ] && echo "not running" && return
  local ET=$(ps -o etime= -p "$PID" 2>/dev/null | tr -d ' ')
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
# PID Tracking
# ============================================================
get_saved_pid()    { local V=$(grep "^${1}=" "$PID_STATE_FILE" 2>/dev/null | cut -d= -f2); echo "${V:-}"; }
save_pid()         { sed -i "/^${1}=/d" "$PID_STATE_FILE" 2>/dev/null; echo "${1}=${2}" >> "$PID_STATE_FILE"; }
update_last_seen() { local N=$(date +%s); sed -i "/^${1}=/d" "$LAST_SEEN_FILE" 2>/dev/null; echo "${1}=${N}" >> "$LAST_SEEN_FILE"; }
get_last_seen()    { local V=$(grep "^${1}=" "$LAST_SEEN_FILE" 2>/dev/null | cut -d= -f2); echo "${V:-}"; }
format_duration()  {
  local S="$1" D=$(($1/86400)) H=$((($1%86400)/3600)) M=$((($1%3600)/60))
  local R=""; [ "$D" -gt 0 ] && R="${D}d "; [ "$H" -gt 0 ] && R="${R}${H}h "; R="${R}${M}m"; echo "$R"
}

# ============================================================
# Restart Counter
# ============================================================
get_restart_count() { local C=$(grep "^${1}=" "$RESTART_COUNT_FILE" 2>/dev/null | cut -d= -f2); echo "${C:-0}"; }
increment_restart_count() {
  local N=$(( $(get_restart_count "$1") + 1 ))
  sed -i "/^${1}=/d" "$RESTART_COUNT_FILE" 2>/dev/null
  echo "${1}=${N}" >> "$RESTART_COUNT_FILE"
}

# ============================================================
# Penalty Tracking
# ============================================================
get_penalty_count() { local V=$(grep "^${1}=" "$PENALTY_FILE" 2>/dev/null | cut -d= -f2); echo "${V:-0}"; }
set_penalty_count() { sed -i "/^${1}=/d" "$PENALTY_FILE" 2>/dev/null; echo "${1}=${2}" >> "$PENALTY_FILE"; }
increment_penalty() { local N=$(( $(get_penalty_count "$1") + 1 )); set_penalty_count "$1" "$N"; echo "$N"; }
reset_penalty()     { set_penalty_count "$1" "0"; log "✅ Node $1 penalties reset to 0"; }

check_proof_status() {
  local LICENSE="$1"
  local LOG_A="$NODE_LOG_DIR/license-${LICENSE}.log"
  local LOG_B="$NODE_LOG_DIR/node-${LICENSE}.log"
  local NODE_LOG=""
  [ -f "$LOG_A" ] && NODE_LOG="$LOG_A" || { [ -f "$LOG_B" ] && NODE_LOG="$LOG_B"; }
  [ -z "$NODE_LOG" ] && echo "UNKNOWN" && return
  local RECENT; RECENT=$(tail -100 "$NODE_LOG" 2>/dev/null)
  echo "$RECENT" | grep -qiE "Successfully submitted proof|Proof of Storage stage handling completed|Collect Proofs handling completed" && echo "PROOF_OK" && return
  echo "$RECENT" | grep -qiE "Failed to send hash proof|failed to submit Send Hash Proof" && echo "MISSED" && return
  echo "UNKNOWN"
}

check_and_update_penalties() {
  local LICENSE="$1" WL=$(get_wallet_label "$1")
  is_node_running "$LICENSE" || return
  local STATUS; STATUS=$(check_proof_status "$LICENSE")
  local CUR; CUR=$(get_penalty_count "$LICENSE")
  if [ "$STATUS" = "PROOF_OK" ]; then
    if [ "$CUR" -gt 0 ]; then
      reset_penalty "$LICENSE"
      send_telegram "✅ <b>Node ${LICENSE} [${WL}] — Penalties Reset</b>
📊 Was: <b>${CUR}</b> → Now: <b>0</b>
🕐 $(now_utc) | $(now_local)"
    fi
    return
  fi
  if [ "$STATUS" = "MISSED" ]; then
    local N; N=$(increment_penalty "$LICENSE")
    log "⚠️ Node $LICENSE [$WL] missed proof — penalties: ${N}/${PENALTY_MAX}"
    if [ "$N" -eq "$PENALTY_WARN" ]; then
      send_telegram "⚠️ <b>Node ${LICENSE} [${WL}] — Penalty Warning</b>
📊 Penalties: <b>${N}/${PENALTY_MAX}</b>
🕐 $(now_utc) | $(now_local)"
    elif [ "$N" -ge "$PENALTY_CRITICAL" ] && [ "$N" -lt "$PENALTY_MAX" ]; then
      send_telegram "🚨 <b>Node ${LICENSE} [${WL}] — CRITICAL Penalty</b>
📊 Penalties: <b>${N}/${PENALTY_MAX}</b>
⚠️ Only $(( PENALTY_MAX - N )) cycle(s) left
🕐 $(now_utc) | $(now_local)"
    elif [ "$N" -ge "$PENALTY_MAX" ]; then
      # AUTO-RESTART DISABLED — actual pool removal takes 15h
      send_telegram "🚫 <b>Node ${LICENSE} [${WL}] — Penalty Threshold</b>
📊 Penalties: <b>${N}/${PENALTY_MAX}</b>
ℹ️ Actual pool removal takes 15h — node will auto re-join
⚠️ Restart manually only if truly stuck
🕐 $(now_utc) | $(now_local)"
    fi
  fi
}

# ============================================================
# Restart Node — per-wallet password + storage check
# ============================================================
restart_node() {
  local LICENSE="$1"
  local WALLET="${NODE_WALLET[$LICENSE]}"
  local PASSWORD=$(get_wallet_password "$LICENSE")
  local WL=$(get_wallet_label "$LICENSE")

  # Storage must be mounted
  if ! check_storage_mounted "$LICENSE"; then
    log "❌ Restart aborted for $LICENSE [$WL] — storage not mounted"
    return 1
  fi

  # Password must be set
  if [ -z "$PASSWORD" ]; then
    log "❌ Restart aborted for $LICENSE [$WL] — wallet password not set"
    send_telegram "🔴 <b>Restart Aborted — Password Missing</b>
🔑 License: <code>${LICENSE}</code> [<b>${WL}</b>]
⚠️ Wallet password is not configured
🕐 $(now_utc) | $(now_local)"
    return 1
  fi

  local OLD_PID=$(get_node_pid "$LICENSE")
  [ -z "$OLD_PID" ] && OLD_PID=$(get_saved_pid "$LICENSE")
  local LS=$(get_last_seen "$LICENSE")
  local OFFLINE="unknown" WENT_DOWN="unknown"
  if [ -n "$LS" ]; then
    OFFLINE=$(format_duration $(( $(date +%s) - LS )))
    WENT_DOWN=$(date -u -d "@${LS}" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || date -u -r "$LS" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null)
  fi

  log "Restarting node $LICENSE [$WL] (offline ~${OFFLINE})..."
  export DENODE_PASSWORD="$PASSWORD"
  nohup "$DENODE_BIN" --address "$WALLET" --license "$LICENSE" \
    >> "$NODE_LOG_DIR/node-${LICENSE}.log" 2>&1 &
  sleep 3

  if is_node_running "$LICENSE"; then
    local NEW_PID=$(get_node_pid "$LICENSE")
    increment_restart_count "$LICENSE"
    save_pid "$LICENSE" "$NEW_PID"
    update_last_seen "$LICENSE"
    local TOTAL=$(get_restart_count "$LICENSE")
    echo "${LICENSE}|$(now_utc)|${WENT_DOWN}|${OFFLINE}|${OLD_PID:-unknown}|${NEW_PID}" >> "$DOWNTIME_LOG"
    log "✅ Node $LICENSE [$WL] restarted (PID: $NEW_PID)"
    send_telegram "✅ <b>Node Restarted</b>
🔑 License: <code>${LICENSE}</code> [<b>${WL}</b>]
🆔 PID: <code>${OLD_PID:-unknown}</code> → <code>${NEW_PID}</code>
🔄 Total: <b>${TOTAL}</b> | ⏱ Offline: <b>${OFFLINE}</b>
🕐 $(now_utc) | $(now_local)"
  else
    log "❌ Node $LICENSE [$WL] FAILED to restart!"
    send_telegram "❌ <b>Node FAILED to Restart</b>
🔑 License: <code>${LICENSE}</code> [<b>${WL}</b>]
⚠️ Manual intervention required!
🕐 $(now_utc) | $(now_local)"
  fi
}

# ============================================================
# Disk Monitoring
# ============================================================
check_disk_space() {
  for LICENSE in "${ALL_LICENSES[@]}"; do
    local DRIVE="${NODE_STORAGE[$LICENSE]}" WL=$(get_wallet_label "$LICENSE")
    [ -z "$DRIVE" ] && continue
    if [ ! -d "$DRIVE" ]; then
      send_telegram "⚠️ <b>Drive Not Mounted</b>
💾 <code>${DRIVE}</code> | 🔑 <code>${LICENSE}</code> [${WL}]
🕐 $(now_utc)"; continue
    fi
    local U=$(df "$DRIVE" | awk 'NR==2 {gsub("%",""); print $5}')
    local UD=$(df -h "$DRIVE" | awk 'NR==2 {print $3}')
    local T=$(df -h "$DRIVE" | awk 'NR==2 {print $2}')
    if [ "$U" -ge "$DISK_ALERT_THRESHOLD" ]; then
      send_telegram "⚠️ <b>Disk Warning</b>
💾 <code>${DRIVE}</code> | [${WL}] <code>${LICENSE}</code>
📊 <b>${U}%</b> — ${UD}/${T}
🕐 $(now_utc)"
    fi
  done
}

get_disk_summary() {
  local L=""
  for LICENSE in "${ALL_LICENSES[@]}"; do
    local DRIVE="${NODE_STORAGE[$LICENSE]}" WL=$(get_wallet_label "$LICENSE")
    [ -z "$DRIVE" ] || [ ! -d "$DRIVE" ] && L="${L}❌ [${WL}] ${LICENSE} — NOT MOUNTED\n" && continue
    local U=$(df "$DRIVE" | awk 'NR==2 {gsub("%",""); print $5}')
    local UD=$(df -h "$DRIVE" | awk 'NR==2 {print $3}')
    local T=$(df -h "$DRIVE" | awk 'NR==2 {print $2}')
    local F=$(df -h "$DRIVE" | awk 'NR==2 {print $4}')
    local I="🟢"; [ "$U" -ge "$DISK_ALERT_THRESHOLD" ] && I="🔴"
    L="${L}${I} [${WL}] <code>${LICENSE}</code>: ${U}% — ${UD}/${T} (free: ${F})\n"
  done
  echo -e "$L"
}

# ============================================================
# Error Alerts — context deadline exceeded removed (P2P noise)
# ============================================================
ERROR_PATTERNS=(
  "roothash mismatch|Roothash Mismatch"
  "failed to unlock account|Password/Unlock Error"
  "already known|Duplicate Transaction"
  "i/o timeout|Network I/O Timeout"
)

check_node_errors() {
  local LICENSE="$1" WL=$(get_wallet_label "$1")
  local LOG_A="$NODE_LOG_DIR/license-${LICENSE}.log"
  local LOG_B="$NODE_LOG_DIR/node-${LICENSE}.log"
  local NODE_LOG=""
  [ -f "$LOG_A" ] && NODE_LOG="$LOG_A" || { [ -f "$LOG_B" ] && NODE_LOG="$LOG_B"; }
  [ -z "$NODE_LOG" ] && return
  local RECENT; RECENT=$(tail -50 "$NODE_LOG" 2>/dev/null)
  for PE in "${ERROR_PATTERNS[@]}"; do
    local PATTERN="${PE%%|*}" LABEL="${PE##*|}"
    if echo "$RECENT" | grep -qi "$PATTERN"; then
      local KEY="${LICENSE}_${PATTERN// /_}" LAST="" NOW=$(date +%s)
      [ -f "$ERROR_STATE_FILE" ] && LAST=$(grep "^${KEY}=" "$ERROR_STATE_FILE" 2>/dev/null | cut -d= -f2)
      if [ -z "$LAST" ] || [ $(( NOW - LAST )) -ge 3600 ]; then
        local LINE; LINE=$(echo "$RECENT" | grep -i "$PATTERN" | tail -1)
        send_telegram "⚠️ <b>Node Error</b>
🔑 <code>${LICENSE}</code> [<b>${WL}</b>]
🔴 <b>${LABEL}</b>
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
  for LICENSE in "${ALL_LICENSES[@]}"; do
    local C=$(get_restart_count "$LICENSE"); [ "$C" -lt 3 ] && continue
    local LAST_ENTRY=$(grep "^${LICENSE}|" "$DOWNTIME_LOG" 2>/dev/null | tail -1)
    [ -z "$LAST_ENTRY" ] && continue
    local LAST_TS=$(echo "$LAST_ENTRY" | cut -d'|' -f2)
    local LAST_EPOCH=$(date -d "$LAST_TS" +%s 2>/dev/null || echo 0)
    if [ $(( NOW - LAST_EPOCH )) -lt 1800 ] && ! is_paused "$LICENSE"; then
      local WL=$(get_wallet_label "$LICENSE")
      log "🔁 Restart loop detected for $LICENSE [$WL] — auto-pausing"
      echo "$LICENSE" >> "$PAUSED_FILE"
      send_telegram "🔁 <b>Restart Loop — Node Auto-Paused</b>
🔑 License: <code>${LICENSE}</code> [<b>${WL}</b>]
🔄 ${C} restarts in last 30 min
🛑 Paused — use /start ${LICENSE} to resume
🕐 $(now_utc) | $(now_local)"
    fi
  done
}

# ============================================================
# Heartbeat
# ============================================================
send_heartbeat() {
  local W1="" W2="" W3="" W4=""
  for LICENSE in "${ALL_LICENSES[@]}"; do
    local WL=$(get_wallet_label "$LICENSE")
    local RC=$(get_restart_count "$LICENSE") PEN=$(get_penalty_count "$LICENSE")
    local PI="🟢"; [ "$PEN" -ge "$PENALTY_WARN" ] && PI="🟡"; [ "$PEN" -ge "$PENALTY_CRITICAL" ] && PI="🟠"
    local PT=""; is_paused "$LICENSE" && PT=" 🛑PAUSED"
    local TT=""
    local TF=$(cat "$GUARD_DIR/tunnel_${LICENSE}" 2>/dev/null || echo "")
    [ "$TF" = "DEAD" ] && TT=" 🔌DEAD"; [ "$TF" = "SILENT" ] && TT=" 🔇SILENT"
    if is_node_running "$LICENSE"; then
      local PID=$(get_node_pid "$LICENSE") UP=$(get_node_uptime "$LICENSE")
      local LINE="🟢 <code>${LICENSE}</code> — PID <code>${PID}</code> — Up: <b>${UP}</b> — R: <b>${RC}</b> — ${PI} P: <b>${PEN}/${PENALTY_MAX}</b>${PT}${TT}\n"
      save_pid "$LICENSE" "$PID"; update_last_seen "$LICENSE"
    else
      local LINE="🔴 <code>${LICENSE}</code> — <b>DOWN</b> — R: <b>${RC}</b>${PT}\n"
    fi
    case "$WL" in W1) W1="${W1}${LINE}" ;; W2) W2="${W2}${LINE}" ;; W3) W3="${W3}${LINE}" ;; W4) W4="${W4}${LINE}" ;; esac
  done
  local MSG="💓 <b>NodePulse HeartBeat (MW)</b>
📍 Host: $(hostname)
🕐 $(now_utc) | $(now_local)"
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
  send_telegram "$MSG"
  date +%s > "$HEARTBEAT_FILE"
  log "💓 Heartbeat sent."
}

should_send_heartbeat() {
  [ ! -f "$HEARTBEAT_FILE" ] && return 0
  [ $(( $(date +%s) - $(cat "$HEARTBEAT_FILE") )) -ge 3600 ] && return 0; return 1
}

# ============================================================
# Daily Summary
# ============================================================
send_daily_summary() {
  local LINES="" UP=0 TOTAL=${#ALL_LICENSES[@]}
  for LICENSE in "${ALL_LICENSES[@]}"; do
    local WL=$(get_wallet_label "$LICENSE")
    if is_node_running "$LICENSE"; then
      LINES="${LINES}🟢 [${WL}] <code>${LICENSE}</code> — Up: <b>$(get_node_uptime $LICENSE)</b>\n"; UP=$(( UP+1 ))
    else
      LINES="${LINES}🔴 [${WL}] <code>${LICENSE}</code> — DOWN\n"
    fi
  done
  send_telegram "📊 <b>Daily Summary (MW)</b>
📅 $(now_utc) | $(now_local)
<b>Nodes (${UP}/${TOTAL}):</b>
$(echo -e "$LINES")
💾 <b>Disk:</b>
$(get_disk_summary)"
  date +%s > "$DAILY_SUMMARY_FILE"; log "📊 Daily summary sent."
}

should_send_daily_summary() {
  local H=$((10#$(TZ="${LOCAL_TIMEZONE}" date '+%H')))
  [ "$H" -ne "$DAILY_SUMMARY_HOUR" ] && return 1
  [ ! -f "$DAILY_SUMMARY_FILE" ] && return 0
  [ $(( $(date +%s) - $(cat "$DAILY_SUMMARY_FILE") )) -lt 82800 ] && return 1; return 0
}

# ============================================================
# DuckDNS
# ============================================================
update_duckdns() {
  [ -z "$DUCKDNS_TOKEN" ] || [ -z "$DUCKDNS_DOMAIN" ] && return
  local R=$(curl -s --max-time 10 "https://www.duckdns.org/update?domains=${DUCKDNS_DOMAIN}&token=${DUCKDNS_TOKEN}&ip=")
  [ "$R" = "OK" ] && log "🌐 DuckDNS updated." || log "⚠️ DuckDNS failed: $R"
}

# ============================================================
# Write status.json
# ============================================================
write_status_json() {
  local VER=$("$DENODE_BIN" --version 2>/dev/null | head -1 || echo "unknown")
  python3 - <<PYEOF
import json, os, subprocess
from datetime import datetime, timezone

all_licenses = [$(printf '"%s",' "${ALL_LICENSES[@]}" | sed 's/,$//')]
pid_file   = os.path.expanduser("$PID_STATE_FILE")
seen_file  = os.path.expanduser("$LAST_SEEN_FILE")
rc_file    = os.path.expanduser("$RESTART_COUNT_FILE")
pen_file   = os.path.expanduser("$PENALTY_FILE")
dt_log     = os.path.expanduser("$DOWNTIME_LOG")
guard_dir  = os.path.expanduser("~/.nodepulse_guard")
paused_file= os.path.expanduser("$PAUSED_FILE")
penalty_max= int("$PENALTY_MAX")

wallet_map = {}
$(for L in "${ALL_LICENSES[@]}"; do echo "wallet_map['${L}'] = '$(get_wallet_label $L)'"; done)

def read_kv(path):
    out={}
    try:
        for line in open(path):
            if "=" in line: k,v=line.strip().split("=",1); out[k]=v
    except: pass
    return out

saved_pids  = read_kv(pid_file)
last_seen   = read_kv(seen_file)
restart_cnt = read_kv(rc_file)
penalties   = read_kv(pen_file)
try: paused_set=set(open(paused_file).read().splitlines())
except: paused_set=set()

def get_score(lic):
    try:
        with open(os.path.join(guard_dir,"score_"+str(lic))) as f: return max(0,min(100,int(f.read().strip())))
    except: return None

def get_tunnel(lic):
    try:
        with open(os.path.join(guard_dir,"tunnel_"+str(lic))) as f: return f.read().strip()
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
    r+=f"{m}m"; return r.strip() or "< 1m"

def get_disk(drive):
    try:
        r=subprocess.run(["df","-h",drive],capture_output=True,text=True)
        p=r.stdout.splitlines()[1].split()
        return {"used":p[2],"total":p[1],"free":p[3],"pct":int(p[4].replace("%",""))}
    except: return None

now_ts=datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
storage={$(for L in "${ALL_LICENSES[@]}"; do echo "\"${L}\":\"${NODE_STORAGE[$L]}\","; done)}
nodes=[]
for lic in all_licenses:
    pid,etime=get_ps_info(lic); running=pid is not None
    saved=saved_pids.get(str(lic),"")
    ls_ts=last_seen.get(str(lic),""); lss=""
    if ls_ts:
        try: dt=datetime.fromtimestamp(int(ls_ts),tz=timezone.utc); lss=dt.strftime("%Y-%m-%d %H:%M:%S UTC")
        except: pass
    nodes.append({"license":lic,"wallet_label":wallet_map.get(str(lic),"??"),
        "status":"running" if running else "down","paused":str(lic) in paused_set,
        "pid":pid or "","uptime":parse_etime(etime) if running else "",
        "restarts":int(restart_cnt.get(str(lic),0)),
        "penalties":int(penalties.get(str(lic),0)),"penalty_max":penalty_max,
        "pid_changed":bool(saved and pid and saved!=pid),
        "old_pid":saved if (saved and pid and saved!=pid) else "",
        "last_seen":lss,"last_downtime":get_last_downtime(lic),
        "disk":get_disk(storage.get(str(lic),"")),"score":get_score(lic),"tunnel":get_tunnel(lic)})

cs_path=os.path.expanduser("$CHAIN_STATUS_FILE")
data={"app":"NodePulse","version":"${VER}","host":"$(hostname)","updated":now_ts,"nodes":nodes,
      "wallets":list(set(wallet_map.values())),
      "chain_status":json.load(open(cs_path)) if os.path.exists(cs_path) else None}
out="$STATUS_JSON"
os.makedirs(os.path.dirname(out),exist_ok=True)
with open(out,"w") as f: json.dump(data,f,indent=2)
print(f"status.json written → {out}")
PYEOF
  log "📡 status.json updated."
}

# ============================================================
# Main Loop
# ============================================================
log "========== NodePulse Monitor Started (MW v2.2) =========="
log "Total nodes: ${#ALL_LICENSES[@]}"

update_duckdns

DOWN_COUNT=0
for LICENSE in "${ALL_LICENSES[@]}"; do
  if is_paused "$LICENSE"; then log "⏸️  Node $LICENSE PAUSED — skipping"; continue; fi
  WL=$(get_wallet_label "$LICENSE")
  if is_node_running "$LICENSE"; then
    PID=$(get_node_pid "$LICENSE"); UP=$(get_node_uptime "$LICENSE")
    log "✅ [${WL}] Node $LICENSE running (PID: $PID, Up: $UP)"
    save_pid "$LICENSE" "$PID"; update_last_seen "$LICENSE"
    TUNNEL=$(check_tunnel_health "$LICENSE")
    echo "$TUNNEL" > "$GUARD_DIR/tunnel_${LICENSE}"
    case "$TUNNEL" in
      DEAD)
        log "🔌 [${WL}] Node $LICENSE — tunnel DEAD"
        send_telegram "🔌 <b>Node ${LICENSE} [${WL}] — Tunnel Dead</b>
⚠️ Port closed and log silent — restarting...
🕐 $(now_utc) | $(now_local)"
        OLD_PID=$(get_node_pid "$LICENSE")
        [ -n "$OLD_PID" ] && kill "$OLD_PID" 2>/dev/null && sleep 2
        restart_node "$LICENSE" ;;
      NO_PORT) log "🔌 [${WL}] Node $LICENSE — port not listening (log active)" ;;
      SILENT)  log "⚠️ [${WL}] Node $LICENSE — log silent (port open)" ;;
      OK)      log "🔗 [${WL}] Node $LICENSE — tunnel OK" ;;
    esac
  else
    log "⚠️ [${WL}] Node $LICENSE DOWN — restarting..."
    DOWN_COUNT=$(( DOWN_COUNT + 1 ))
    send_telegram "⚠️ <b>Node Down</b>
🔑 <code>${LICENSE}</code> [<b>${WL}</b>]
🔄 Attempting restart...
🕐 $(now_utc) | $(now_local)"
    restart_node "$LICENSE"
  fi
done

[ "$DOWN_COUNT" -eq 0 ] && log "All ${#ALL_LICENSES[@]} nodes running." || log "$DOWN_COUNT node(s) restarted."

check_disk_space
for LICENSE in "${ALL_LICENSES[@]}"; do is_paused "$LICENSE" && continue; check_node_errors "$LICENSE"; done
for LICENSE in "${ALL_LICENSES[@]}"; do is_paused "$LICENSE" && continue; check_and_update_penalties "$LICENSE"; done
watchdog_check
should_send_heartbeat     && send_heartbeat
should_send_daily_summary && send_daily_summary
write_status_json

log "========== NodePulse Monitor Finished =========="
