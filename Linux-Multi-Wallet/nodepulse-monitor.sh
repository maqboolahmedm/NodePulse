#!/bin/bash

# ============================================================
# DeNet Node Monitor — Multi-Wallet Version
# NodePulse v2.1 — Added: pause check, tunnel health detection
# Supports up to 4 wallets with different passwords
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
TUNNEL_SILENCE_THRESHOLD=4800

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

mkdir -p "$NODE_LOG_DIR" "$GUARD_DIR" "$(dirname $STATUS_JSON)" 2>/dev/null || true
touch "$PID_STATE_FILE" "$LAST_SEEN_FILE" "$DOWNTIME_LOG" "$PENALTY_FILE" "$PAUSED_FILE"

# ============================================================
# Build combined license list
# ============================================================
ALL_LICENSES=()
[ ${#WALLET_1_LICENSES[@]} -gt 0 ] && ALL_LICENSES+=("${WALLET_1_LICENSES[@]}")
[ ${#WALLET_2_LICENSES[@]} -gt 0 ] && ALL_LICENSES+=("${WALLET_2_LICENSES[@]}")
[ ${#WALLET_3_LICENSES[@]} -gt 0 ] && ALL_LICENSES+=("${WALLET_3_LICENSES[@]}")
[ ${#WALLET_4_LICENSES[@]} -gt 0 ] && ALL_LICENSES+=("${WALLET_4_LICENSES[@]}")

get_wallet_password() {
  local LICENSE="$1"
  local WALLET="${NODE_WALLET[$LICENSE]}"
  if   [ "$WALLET" = "$WALLET_1_ADDRESS" ]; then echo "$WALLET_1_PASSWORD"
  elif [ "$WALLET" = "$WALLET_2_ADDRESS" ]; then echo "$WALLET_2_PASSWORD"
  elif [ "$WALLET" = "$WALLET_3_ADDRESS" ]; then echo "$WALLET_3_PASSWORD"
  elif [ "$WALLET" = "$WALLET_4_ADDRESS" ]; then echo "$WALLET_4_PASSWORD"
  fi
}

get_wallet_label() {
  local LICENSE="$1"
  local WALLET="${NODE_WALLET[$LICENSE]}"
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
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    -d text="${1}" \
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
# Tunnel Health Check
# ============================================================
check_tunnel_health() {
  local LICENSE="$1"
  local PORT="${NODE_PORT[$LICENSE]}"
  local LOG="$NODE_LOG_DIR/node-${LICENSE}.log"

  local PORT_OPEN=0 LOG_FRESH=0

  if [ -n "$PORT" ] && ss -tlnp 2>/dev/null | grep -q ":${PORT}"; then
    PORT_OPEN=1
  fi

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
  local PID=$(get_node_pid "$1")
  [ -z "$PID" ] && echo "not running" && return
  local ETIME=$(ps -o etime= -p "$PID" 2>/dev/null | tr -d ' ')
  [ -z "$ETIME" ] && echo "unknown" && return
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
  [ -z "$R"         ] && R="< 1m"
  echo "$R"
}

# ============================================================
# PID Tracking
# ============================================================
get_saved_pid() { local V=$(grep "^${1}=" "$PID_STATE_FILE" 2>/dev/null | cut -d= -f2); echo "${V:-}"; }
save_pid()      { sed -i "/^${1}=/d" "$PID_STATE_FILE" 2>/dev/null; echo "${1}=${2}" >> "$PID_STATE_FILE"; }
update_last_seen() { local N=$(date +%s); sed -i "/^${1}=/d" "$LAST_SEEN_FILE" 2>/dev/null; echo "${1}=${N}" >> "$LAST_SEEN_FILE"; }
get_last_seen() { local V=$(grep "^${1}=" "$LAST_SEEN_FILE" 2>/dev/null | cut -d= -f2); echo "${V:-}"; }

format_duration() {
  local SECS="$1"
  local DAYS=$(( SECS / 86400 )) HOURS=$(( (SECS % 86400) / 3600 )) MINS=$(( (SECS % 3600) / 60 ))
  local R=""
  [ "$DAYS"  -gt 0 ] && R="${DAYS}d "
  [ "$HOURS" -gt 0 ] && R="${R}${HOURS}h "
  R="${R}${MINS}m"; echo "$R"
}

# ============================================================
# Restart Counter
# ============================================================
get_restart_count() { local C=$(grep "^${1}=" "$RESTART_COUNT_FILE" 2>/dev/null | cut -d= -f2); echo "${C:-0}"; }
increment_restart_count() {
  local NEW=$(( $(get_restart_count "$1") + 1 ))
  sed -i "/^${1}=/d" "$RESTART_COUNT_FILE" 2>/dev/null
  echo "${1}=${NEW}" >> "$RESTART_COUNT_FILE"
}

# ============================================================
# Penalty Tracking
# ============================================================
get_penalty_count() { local V=$(grep "^${1}=" "$PENALTY_FILE" 2>/dev/null | cut -d= -f2); echo "${V:-0}"; }
set_penalty_count() { sed -i "/^${1}=/d" "$PENALTY_FILE" 2>/dev/null; echo "${1}=${2}" >> "$PENALTY_FILE"; }
increment_penalty() { local N=$(( $(get_penalty_count "$1") + 1 )); set_penalty_count "$1" "$N"; echo "$N"; }
reset_penalty()     { set_penalty_count "$1" "0"; log "✅ Node $1 penalties reset to 0"; }

# ============================================================
# Restart Node
# ============================================================
restart_node() {
  local LICENSE="$1"
  local WALLET="${NODE_WALLET[$LICENSE]}"
  local PASSWORD=$(get_wallet_password "$LICENSE")
  local WL=$(get_wallet_label "$LICENSE")
  local OLD_PID=$(get_node_pid "$LICENSE")
  [ -z "$OLD_PID" ] && OLD_PID=$(get_saved_pid "$LICENSE")

  local LAST_SEEN OFFLINE_DURATION WENT_DOWN_UTC
  LAST_SEEN=$(get_last_seen "$LICENSE")
  if [ -n "$LAST_SEEN" ]; then
    local NOW=$(date +%s)
    OFFLINE_DURATION=$(format_duration $(( NOW - LAST_SEEN )))
    WENT_DOWN_UTC=$(date -u -d "@${LAST_SEEN}" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || \
                    date -u -r "$LAST_SEEN"     '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null)
  else
    OFFLINE_DURATION="unknown"; WENT_DOWN_UTC="unknown"
  fi

  log "Restarting node $LICENSE [${WL}] (offline ~${OFFLINE_DURATION})..."
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
    echo "${LICENSE}|$(now_utc)|${WENT_DOWN_UTC}|${OFFLINE_DURATION}|${OLD_PID:-unknown}|${NEW_PID}" >> "$DOWNTIME_LOG"
    log "✅ Node $LICENSE [${WL}] restarted (PID: $NEW_PID)"
    send_telegram "✅ <b>Node Restarted</b>
🔑 License: <code>${LICENSE}</code> [<b>${WL}</b>]
🆔 PID: <code>${OLD_PID:-unknown}</code> → <code>${NEW_PID}</code>
🔄 Total Restarts: <b>${TOTAL}</b>
⏱ Offline: <b>${OFFLINE_DURATION}</b>
🕐 $(now_utc) | $(now_local)
📍 Host: $(hostname)"
  else
    log "❌ Node $LICENSE [${WL}] FAILED to restart!"
    send_telegram "❌ <b>Node FAILED to Restart</b>
🔑 License: <code>${LICENSE}</code> [<b>${WL}</b>]
⚠️ Manual intervention required!
🕐 $(now_utc)
📍 Host: $(hostname)"
  fi
}

# ============================================================
# Disk Monitoring
# ============================================================
check_disk_space() {
  for LICENSE in "${ALL_LICENSES[@]}"; do
    local DRIVE="${NODE_STORAGE[$LICENSE]}"
    [ -z "$DRIVE" ] && continue
    if [ ! -d "$DRIVE" ]; then
      send_telegram "⚠️ <b>Drive Not Mounted</b>
💾 Drive: <code>${DRIVE}</code>
🔑 License: <code>${LICENSE}</code> [$(get_wallet_label $LICENSE)]
🕐 $(now_utc)"
      continue
    fi
    local USAGE=$(df "$DRIVE" | awk 'NR==2 {gsub("%",""); print $5}')
    local USED=$(df -h "$DRIVE" | awk 'NR==2 {print $3}')
    local TOTAL=$(df -h "$DRIVE" | awk 'NR==2 {print $2}')
    if [ "$USAGE" -ge "$DISK_ALERT_THRESHOLD" ]; then
      send_telegram "⚠️ <b>Disk Space Warning</b>
💾 Drive: <code>${DRIVE}</code>
🔑 License: <code>${LICENSE}</code> [$(get_wallet_label $LICENSE)]
📊 Usage: <b>${USAGE}%</b> — ${USED}/${TOTAL}
🕐 $(now_utc)"
    fi
  done
}

get_disk_summary() {
  local LINES=""
  for LICENSE in "${ALL_LICENSES[@]}"; do
    local DRIVE="${NODE_STORAGE[$LICENSE]}"
    [ -z "$DRIVE" ] || [ ! -d "$DRIVE" ] && LINES="${LINES}❌ ${LICENSE} — NOT MOUNTED\n" && continue
    local USAGE=$(df "$DRIVE" | awk 'NR==2 {gsub("%",""); print $5}')
    local USED=$(df -h "$DRIVE" | awk 'NR==2 {print $3}')
    local TOTAL=$(df -h "$DRIVE" | awk 'NR==2 {print $2}')
    local FREE=$(df -h "$DRIVE" | awk 'NR==2 {print $4}')
    local ICON="🟢"; [ "$USAGE" -ge "$DISK_ALERT_THRESHOLD" ] && ICON="🔴"
    local WL=$(get_wallet_label "$LICENSE")
    LINES="${LINES}${ICON} [${WL}] <code>${LICENSE}</code>: ${USAGE}% — ${USED}/${TOTAL} (free: ${FREE})\n"
  done
  echo -e "$LINES"
}

# ============================================================
# Heartbeat
# ============================================================
send_heartbeat() {
  local W1_LINES="" W2_LINES="" W3_LINES="" W4_LINES=""
  for LICENSE in "${ALL_LICENSES[@]}"; do
    local WL=$(get_wallet_label "$LICENSE")
    local RC=$(get_restart_count "$LICENSE")
    local PEN=$(get_penalty_count "$LICENSE")
    local PEN_ICON="🟢"
    [ "$PEN" -ge "$PENALTY_WARN" ]     && PEN_ICON="🟡"
    [ "$PEN" -ge "$PENALTY_CRITICAL" ] && PEN_ICON="🟠"
    local PAUSE_TAG=""; is_paused "$LICENSE" && PAUSE_TAG=" 🛑PAUSED"
    local TUNNEL_TAG=""
    local T; T=$(cat "$GUARD_DIR/tunnel_${LICENSE}" 2>/dev/null || echo "")
    [ "$T" = "DEAD" ]    && TUNNEL_TAG=" 🔌DEAD"
    [ "$T" = "SILENT" ]  && TUNNEL_TAG=" 🔇SILENT"
    [ "$T" = "NO_PORT" ] && TUNNEL_TAG=" ⚠️NO_PORT"

    if is_node_running "$LICENSE"; then
      local PID=$(get_node_pid "$LICENSE"); local UP=$(get_node_uptime "$LICENSE")
      local LINE="🟢 <code>${LICENSE}</code> — PID <code>${PID}</code> — Up: <b>${UP}</b> — R: <b>${RC}</b> — ${PEN_ICON} P: <b>${PEN}/${PENALTY_MAX}</b>${PAUSE_TAG}${TUNNEL_TAG}\n"
      save_pid "$LICENSE" "$PID"; update_last_seen "$LICENSE"
    else
      local LINE="🔴 <code>${LICENSE}</code> — <b>DOWN</b> — R: <b>${RC}</b>${PAUSE_TAG}\n"
    fi
    case "$WL" in
      W1) W1_LINES="${W1_LINES}${LINE}" ;;
      W2) W2_LINES="${W2_LINES}${LINE}" ;;
      W3) W3_LINES="${W3_LINES}${LINE}" ;;
      W4) W4_LINES="${W4_LINES}${LINE}" ;;
    esac
  done
  local MSG="💓 <b>DeNet Node Monitor HeartBeat</b>
📍 Host: $(hostname)
🕐 $(now_utc) | $(now_local)"
  [ -n "$W1_LINES" ] && MSG="${MSG}

<b>💼 Wallet 1:</b>
$(echo -e "$W1_LINES")"
  [ -n "$W2_LINES" ] && MSG="${MSG}

<b>💼 Wallet 2:</b>
$(echo -e "$W2_LINES")"
  [ -n "$W3_LINES" ] && MSG="${MSG}

<b>💼 Wallet 3:</b>
$(echo -e "$W3_LINES")"
  [ -n "$W4_LINES" ] && MSG="${MSG}

<b>💼 Wallet 4:</b>
$(echo -e "$W4_LINES")"
  send_telegram "$MSG"
  date +%s > "$HEARTBEAT_FILE"
  log "💓 Heartbeat sent."
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
  for LICENSE in "${ALL_LICENSES[@]}"; do
    local WL=$(get_wallet_label "$LICENSE")
    if is_node_running "$LICENSE"; then
      local PID=$(get_node_pid "$LICENSE"); local UP_T=$(get_node_uptime "$LICENSE")
      LINES="${LINES}🟢 [${WL}] <code>${LICENSE}</code> — PID <code>${PID}</code> — Up: <b>${UP_T}</b>\n"
      UP=$(( UP + 1 ))
    else
      LINES="${LINES}🔴 [${WL}] <code>${LICENSE}</code> — DOWN\n"
      DOWN=$(( DOWN + 1 ))
    fi
  done
  local TOTAL=${#ALL_LICENSES[@]}
  send_telegram "📊 <b>DeNet Daily Summary</b>
📅 $(now_utc) | $(now_local)
📍 Host: $(hostname)

<b>Nodes (${UP}/${TOTAL} online):</b>
$(echo -e "$LINES")
💾 <b>Disk:</b>
$(get_disk_summary)"
  date +%s > "$DAILY_SUMMARY_FILE"
  log "📊 Daily summary sent."
}

should_send_daily_summary() {
  local CURRENT_HOUR=$((10#$(TZ="${LOCAL_TIMEZONE}" date '+%H')))
  [ "$CURRENT_HOUR" -ne "$DAILY_SUMMARY_HOUR" ] && return 1
  [ ! -f "$DAILY_SUMMARY_FILE" ] && return 0
  local DIFF=$(( $(date +%s) - $(cat "$DAILY_SUMMARY_FILE") ))
  [ "$DIFF" -lt 82800 ] && return 1; return 0
}

# ============================================================
# DuckDNS
# ============================================================
update_duckdns() {
  [ -z "$DUCKDNS_TOKEN" ] || [ -z "$DUCKDNS_DOMAIN" ] && return
  local R=$(curl -s --max-time 10 \
    "https://www.duckdns.org/update?domains=${DUCKDNS_DOMAIN}&token=${DUCKDNS_TOKEN}&ip=")
  [ "$R" = "OK" ] && log "🌐 DuckDNS updated." || log "⚠️ DuckDNS failed: $R"
}

# ============================================================
# Write status.json
# ============================================================
write_status_json() {
  local DENODE_VERSION=$("$DENODE_BIN" --version 2>/dev/null | head -1 || echo "unknown")

  python3 - <<PYEOF
import json, os, subprocess
from datetime import datetime, timezone

all_licenses = [$(printf '"%s",' "${ALL_LICENSES[@]}" | sed 's/,$//')]
pid_file  = os.path.expanduser("$PID_STATE_FILE")
seen_file = os.path.expanduser("$LAST_SEEN_FILE")
rc_file   = os.path.expanduser("$RESTART_COUNT_FILE")
pen_file  = os.path.expanduser("$PENALTY_FILE")
dt_log    = os.path.expanduser("$DOWNTIME_LOG")
penalty_max = int("$PENALTY_MAX")
guard_dir   = os.path.expanduser("~/.nodepulse_guard")
paused_file = os.path.expanduser("$PAUSED_FILE")

wallet_map = {}
$(for L in "${ALL_LICENSES[@]}"; do
  echo "wallet_map['${L}'] = '$(get_wallet_label $L)'"
done)

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
    try: return set(open(paused_file).read().splitlines())
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
                pid = parts[1]
                r2 = subprocess.run(["ps", "-o", "etime=", "-p", pid], capture_output=True, text=True)
                return pid, r2.stdout.strip()
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

def get_disk(storage_path):
    try:
        r = subprocess.run(["df", "-h", storage_path], capture_output=True, text=True)
        parts = r.stdout.splitlines()[1].split()
        return {"used": parts[2], "total": parts[1], "free": parts[3], "pct": int(parts[4].replace("%",""))}
    except: return None

now_ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
nodes = []
for lic in all_licenses:
    pid, etime = get_ps_info(lic)
    running = pid is not None
    saved_pid = saved_pids.get(str(lic), "")
    pid_changed = saved_pid and pid and saved_pid != pid
    ls_ts = last_seen.get(str(lic), "")
    last_seen_str = ""
    if ls_ts:
        try:
            dt = datetime.fromtimestamp(int(ls_ts), tz=timezone.utc)
            last_seen_str = dt.strftime("%Y-%m-%d %H:%M:%S UTC")
        except: pass
    storage_paths = {$(for L in "${ALL_LICENSES[@]}"; do echo "\"${L}\": \"${NODE_STORAGE[$L]}\","; done)}
    disk = get_disk(storage_paths.get(str(lic), ""))
    nodes.append({
        "license":       lic,
        "wallet_label":  wallet_map.get(str(lic), "??"),
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
    "app":     "NodePulse",
    "version": "${DENODE_VERSION}",
    "host":    "$(hostname)",
    "updated": now_ts,
    "nodes":   nodes,
    "wallets": list(set(wallet_map.values()))
}

out = "$STATUS_JSON"
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w") as f:
    json.dump(data, f, indent=2)
print(f"status.json written → {out}")
PYEOF
  log "📡 status.json updated."
}

# ============================================================
# Main Loop
# ============================================================
log "========== DeNet Multi-Wallet Monitor Started =========="
log "Total nodes: ${#ALL_LICENSES[@]}"

update_duckdns

DOWN_COUNT=0
for LICENSE in "${ALL_LICENSES[@]}"; do

  # ── PAUSE CHECK ───────────────────────────────────────────
  if is_paused "$LICENSE"; then
    log "⏸️  Node $LICENSE is PAUSED — skipping all checks"
    continue
  fi
  # ─────────────────────────────────────────────────────────

  WL=$(get_wallet_label "$LICENSE")
  if is_node_running "$LICENSE"; then
    PID=$(get_node_pid "$LICENSE")
    UP=$(get_node_uptime "$LICENSE")
    log "✅ [${WL}] Node $LICENSE running (PID: $PID, Up: $UP)"
    save_pid "$LICENSE" "$PID"
    update_last_seen "$LICENSE"

    # ── TUNNEL HEALTH CHECK ─────────────────────────────────
    TUNNEL=$(check_tunnel_health "$LICENSE")
    echo "$TUNNEL" > "$GUARD_DIR/tunnel_${LICENSE}"
    case "$TUNNEL" in
      DEAD)
        log "🔌 [${WL}] Node $LICENSE — tunnel DEAD (port closed + log silent)"
        send_telegram "🔌 <b>Node ${LICENSE} — Tunnel Dead</b>
🔑 License: <code>${LICENSE}</code> [<b>${WL}</b>]
⚠️ Process running but port closed and log silent
🔄 Restarting to re-establish tunnel...
🕐 $(now_utc) | $(now_local)
📍 Host: $(hostname)"
        OLD_PID=$(get_node_pid "$LICENSE")
        # [ -n "$OLD_PID" ] && kill "$OLD_PID" 2>/dev/null && sleep 2
        # restart_node "$LICENSE"
        ;;
      NO_PORT)
        log "🔌 [${WL}] Node $LICENSE — port not listening (log active)"
        ;;
      SILENT)
        log "⚠️ [${WL}] Node $LICENSE — log silent >$((TUNNEL_SILENCE_THRESHOLD/60))min"
        ;;
      OK)
        log "🔗 [${WL}] Node $LICENSE — tunnel OK"
        ;;
    esac
    # ───────────────────────────────────────────────────────

  else
    log "⚠️ [${WL}] Node $LICENSE DOWN — restarting..."
    DOWN_COUNT=$(( DOWN_COUNT + 1 ))
    send_telegram "⚠️ <b>Node Down Detected</b>
🔑 License: <code>${LICENSE}</code> [<b>${WL}</b>]
🔄 Attempting restart...
🕐 $(now_utc) | $(now_local)
📍 Host: $(hostname)"
    restart_node "$LICENSE"
  fi
done

[ "$DOWN_COUNT" -eq 0 ] && log "All ${#ALL_LICENSES[@]} nodes running normally." || log "$DOWN_COUNT node(s) restarted."

check_disk_space
should_send_heartbeat     && send_heartbeat
should_send_daily_summary && send_daily_summary
write_status_json

log "========== DeNet Multi-Wallet Monitor Finished =========="
