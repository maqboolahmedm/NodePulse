#!/bin/bash

# ============================================================
# NodePulse Guard — Community Intelligence Agent
# Linux Multi-Wallet Version
# v1.1 — Added: pause check, TUNNEL_DEAD detection
# github.com/maqboolahmedm/NodePulse
# ============================================================

TELEGRAM_BOT_TOKEN="YOUR_TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="YOUR_TELEGRAM_CHAT_ID"
LICENSES=(YOUR_LICENSE_1 YOUR_LICENSE_2 YOUR_LICENSE_3)
WALLET_ADDRESS="YOUR_WALLET_ADDRESS"
DENODE_BIN="/usr/bin/denode"
NODE_LOG_DIR="$HOME/.denode/logs"
LOCAL_TIMEZONE="YOUR_TIMEZONE"
PENALTY_FILE="$HOME/.denode/.node_penalties"
PENALTY_MAX=10
COOLDOWN_MINUTES=30
GUARD_DIR="$HOME/.nodepulse_guard"
GUARD_LOG="$GUARD_DIR/guard.log"
GUARD_COOLDOWN="$GUARD_DIR/cooldowns"
GUARD_HEALTH="$GUARD_DIR/health_scores"
LAST_REPORT_FILE="$GUARD_DIR/.last_report"
PAUSED_FILE="$GUARD_DIR/paused_nodes"

TUNNEL_SILENCE_THRESHOLD=600

mkdir -p "$GUARD_DIR"
touch "$GUARD_LOG" "$GUARD_COOLDOWN" "$GUARD_HEALTH" "$PAUSED_FILE"

now_utc()   { date -u '+%Y-%m-%d %H:%M:%S UTC'; }
now_local() { TZ="${LOCAL_TIMEZONE}" date '+%H:%M:%S %Z'; }
log()       { echo "[$(now_utc) | $(now_local)] [GUARD] $1" | tee -a "$GUARD_LOG"; }

send_telegram() {
  curl -s --max-time 15 -X POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" -d text="${1}" \
    -d parse_mode="HTML" > /dev/null 2>&1
}

is_node_running() {
  ps aux | grep -v grep | grep "$DENODE_BIN" | grep -- "--license $1" > /dev/null 2>&1
}

is_paused() {
  grep -qx "$1" "$PAUSED_FILE" 2>/dev/null
}

get_penalty_count() {
  local V=$(grep "^${1}=" "$PENALTY_FILE" 2>/dev/null | cut -d= -f2)
  echo "${V:-0}"
}

get_health_score() {
  local V=$(grep "^${1}=" "$GUARD_HEALTH" 2>/dev/null | cut -d= -f2)
  echo "${V:-100}"
}

update_health_score() {
  local LIC="$1" DELTA="$2"
  local CUR=$(get_health_score "$LIC")
  local NEW=$(( CUR + DELTA ))
  [ "$NEW" -gt 100 ] && NEW=100
  [ "$NEW" -lt 0   ] && NEW=0
  sed -i "/^${LIC}=/d" "$GUARD_HEALTH" 2>/dev/null
  echo "${LIC}=${NEW}" >> "$GUARD_HEALTH"
  echo "$NEW" > "${GUARD_DIR}/score_${LIC}"
}

is_in_cooldown() {
  local KEY="${1}_${2}"
  local LAST=$(grep "^${KEY}=" "$GUARD_COOLDOWN" 2>/dev/null | cut -d= -f2)
  [ -z "$LAST" ] && return 1
  local DIFF=$(( $(date +%s) - LAST ))
  [ "$DIFF" -lt $(( COOLDOWN_MINUTES * 60 )) ] && return 0
  return 1
}

set_cooldown() {
  local KEY="${1}_${2}"
  sed -i "/^${KEY}=/d" "$GUARD_COOLDOWN" 2>/dev/null
  echo "${KEY}=$(date +%s)" >> "$GUARD_COOLDOWN"
}

# ============================================================
# Watcher
# ============================================================
watch_node() {
  local LICENSE="$1"
  local LOG_A="$NODE_LOG_DIR/node-${LICENSE}.log"
  local LOG_B="$NODE_LOG_DIR/license-${LICENSE}.log"
  local LOG_FILE; [ -f "$LOG_A" ] && LOG_FILE="$LOG_A" || LOG_FILE="$LOG_B"
  [ ! -f "$LOG_FILE" ] && echo "NO_LOG~No log file found~0~none" && return

  python3 - "$LOG_FILE" "$TUNNEL_SILENCE_THRESHOLD" <<'PYEOF'
import sys, re, os, time
from datetime import datetime, timezone, timedelta
from collections import Counter

log_file          = sys.argv[1]
silence_threshold = int(sys.argv[2])

try:
    with open(log_file, 'rb') as f:
        f.seek(0, 2); size = f.tell(); f.seek(max(0, size - 102400))
        lines = f.read().decode('utf-8', errors='ignore').splitlines()
except Exception as e:
    print(f"READ_ERROR~Cannot read log: {e}~0~none"); sys.exit(0)

log_age_secs = int(time.time() - os.path.getmtime(log_file))
log_silent   = log_age_secs > silence_threshold

now  = datetime.now(timezone.utc)
IST  = timedelta(hours=5, minutes=30)
TS   = re.compile(r'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})')
POOL = re.compile(r'License ID is in (\d+) pool')
STG  = re.compile(r'(?:Current Stage|Next Stage):\s*([\w ]+\w)')

issues, last_proof_min, last_stage, pool_number, last_seen_ts = [], None, "", "", None

for line in reversed(lines):
    m = TS.search(line)
    ts = None
    if m:
        try:
            dt = datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S")
            ts = (dt - IST).replace(tzinfo=timezone.utc)
            if last_seen_ts is None: last_seen_ts = ts
        except: pass
    if not pool_number:
        m2 = POOL.search(line)
        if m2: pool_number = m2.group(1)
    if not last_stage:
        m3 = STG.search(line)
        if m3:
            s = m3.group(1).strip()
            if s not in ('Next Stage',): last_stage = s
    if last_proof_min is None and (
        'Collect Proofs handling completed' in line or
        'Stage Collect Proofs handling completed' in line
    ):
        eff = ts or last_seen_ts
        if eff: last_proof_min = (now - eff).total_seconds() / 60
    ll = line.lower()
    if   'gas price less than block base fee' in ll:                                issues.append('LOW_GAS')
    elif 'replacement transaction underpriced' in ll:                               issues.append('TX_UNDERPRICED')
    elif 'insufficient funds' in ll:                                                issues.append('NO_FUNDS')
    elif 'connection refused' in ll or 'dial tcp' in ll:                            issues.append('RPC_ERROR')
    elif 'context deadline exceeded' in ll:                                         issues.append('RPC_TIMEOUT')
    elif 'transaction was not mined' in ll or 'failed to wait for transaction mining' in ll:
                                                                                    issues.append('TX_NOT_MINED')
    elif 'failed to send proof' in ll and 'gas' not in ll and 'replacement' not in ll and 'mined' not in ll:
                                                                                    issues.append('PROOF_FAIL')

counts = Counter(issues)

if last_proof_min is not None:
    if   last_proof_min < 95:  chain = "HEALTHY"
    elif last_proof_min < 190: chain = "PENDING"
    else:                      chain = "STALE"
else: chain = "UNKNOWN"

age_str = f"{int(last_proof_min)}m" if last_proof_min else "unknown"

serious = []
if counts['NO_FUNDS']       >= 1: serious.append(('NO_FUNDS',       95))
if counts['TX_NOT_MINED']   >= 3: serious.append(('TX_NOT_MINED',   80))
if counts['PROOF_FAIL']     >= 2: serious.append(('PROOF_FAIL',     70))
if counts['RPC_ERROR']      >= 2: serious.append(('RPC_ERROR',      75))
if counts['RPC_TIMEOUT']    >= 3: serious.append(('RPC_TIMEOUT',    60))
if counts['LOW_GAS']        >= 3: serious.append(('LOW_GAS',        50))
if counts['TX_UNDERPRICED'] >= 3: serious.append(('TX_UNDERPRICED', 45))

if log_silent and last_proof_min is not None and last_proof_min < 190:
    serious.insert(0, ('TUNNEL_DEAD', 85))

if not serious:
    if   chain == "HEALTHY": print(f"HEALTHY~Last proof {age_str} ago | Pool {pool_number} | {last_stage}~100~none")
    elif chain == "PENDING": print(f"PENDING~Last proof {age_str} ago | Pool {pool_number} | {last_stage}~60~monitor")
    elif chain == "STALE":   print(f"STALE~No proof for {age_str} | Pool {pool_number} | {last_stage}~70~monitor")
    else:                    print(f"STARTING~Warming up | Pool {pool_number} | {last_stage}~50~none")
else:
    top  = serious[0]
    msgs = {
        'NO_FUNDS':      'Insufficient PEAQ balance',
        'TX_NOT_MINED':  'Transaction not mined',
        'PROOF_FAIL':    'Proof failing repeatedly',
        'RPC_ERROR':     'RPC refusing connections',
        'RPC_TIMEOUT':   'RPC timing out',
        'LOW_GAS':       'Gas spike (transient)',
        'TX_UNDERPRICED':'Transaction underpriced',
        'TUNNEL_DEAD':   f'Log silent {log_age_secs}s — tunnel likely dropped',
    }
    print(f"{top[0]}~{msgs.get(top[0],'Unknown')} | Pool {pool_number} | {last_stage}~{top[1]}~monitor")
PYEOF
}

# ============================================================
# Main
# ============================================================
log "=========================================="
log "  NodePulse Guard Started (MW)"
log "  Nodes: ${#LICENSES[@]} | Cooldown: ${COOLDOWN_MINUTES}min"
log "=========================================="

ISSUES=0
REPORT_LINES=""
ALL_HEALTHY=1

for LICENSE in "${LICENSES[@]}"; do

  # ── PAUSE CHECK ────────────────────────────────────────────
  if is_paused "$LICENSE"; then
    log "⏸️  Node $LICENSE is PAUSED — skipping guard"
    REPORT_LINES="${REPORT_LINES}⏸️ <code>${LICENSE}</code> — PAUSED\n"
    continue
  fi
  # ──────────────────────────────────────────────────────────

  RESULT=$(watch_node "$LICENSE")
  CODE=$(echo "$RESULT" | cut -d'~' -f1)
  MSG=$(echo  "$RESULT" | cut -d'~' -f2)
  CONF=$(echo "$RESULT" | cut -d'~' -f3)
  SCORE=$(get_health_score "$LICENSE")

  case "$CODE" in
    HEALTHY)
      log "✅ Node $LICENSE — HEALTHY ($MSG)"
      update_health_score "$LICENSE" "+2"
      REPORT_LINES="${REPORT_LINES}🟢 <code>${LICENSE}</code> — HEALTHY | ${MSG}\n"
      ;;
    STARTING)
      REPORT_LINES="${REPORT_LINES}⏳ <code>${LICENSE}</code> — Starting up | ${MSG}\n"
      ;;
    PENDING)
      ALL_HEALTHY=0
      REPORT_LINES="${REPORT_LINES}🟡 <code>${LICENSE}</code> — PENDING | ${MSG}\n"
      if ! is_in_cooldown "$LICENSE" "$CODE"; then
        set_cooldown "$LICENSE" "$CODE"
        update_health_score "$LICENSE" "-3"
        send_telegram "🟡 <b>NodePulse Guard — Pending</b>
🔑 License: <code>${LICENSE}</code>
📋 ${MSG}
🎯 Confidence: <b>${CONF}%</b> | 💊 Health: <b>${SCORE}/100</b>
🕐 $(now_utc) | $(now_local)"
      fi
      ;;
    TUNNEL_DEAD)
      ALL_HEALTHY=0; ISSUES=$(( ISSUES + 1 ))
      REPORT_LINES="${REPORT_LINES}🔌 <code>${LICENSE}</code> — TUNNEL_DEAD | ${MSG}\n"
      if ! is_in_cooldown "$LICENSE" "$CODE"; then
        set_cooldown "$LICENSE" "$CODE"
        update_health_score "$LICENSE" "-10"
        send_telegram "🔌 <b>NodePulse Guard — Tunnel Dead</b>
🔑 License: <code>${LICENSE}</code>
📋 ${MSG}
🎯 Confidence: <b>${CONF}%</b> | 💊 Health: <b>${SCORE}/100</b>
⚠️ Node process running but log is silent — tunnel likely dropped
🔄 Monitor will restart node on next run
🕐 $(now_utc) | $(now_local)"
      fi
      ;;
    STALE|PROOF_FAIL|RPC_ERROR|RPC_TIMEOUT|TX_NOT_MINED)
      ALL_HEALTHY=0; ISSUES=$(( ISSUES + 1 ))
      REPORT_LINES="${REPORT_LINES}🔴 <code>${LICENSE}</code> — ${CODE} | ${MSG}\n"
      if ! is_in_cooldown "$LICENSE" "$CODE"; then
        set_cooldown "$LICENSE" "$CODE"
        update_health_score "$LICENSE" "-8"
        send_telegram "🔴 <b>NodePulse Guard Alert — ${CODE}</b>
🔑 License: <code>${LICENSE}</code>
📋 ${MSG}
🎯 Confidence: <b>${CONF}%</b> | 💊 Health: <b>${SCORE}/100</b>
🕐 $(now_utc) | $(now_local)"
      fi
      ;;
    NO_FUNDS)
      ALL_HEALTHY=0; ISSUES=$(( ISSUES + 1 ))
      REPORT_LINES="${REPORT_LINES}🚨 <code>${LICENSE}</code> — NO_FUNDS | ${MSG}\n"
      if ! is_in_cooldown "$LICENSE" "$CODE"; then
        set_cooldown "$LICENSE" "$CODE"
        update_health_score "$LICENSE" "-20"
        send_telegram "🚨 <b>NodePulse Guard URGENT — Insufficient Funds</b>
🔑 License: <code>${LICENSE}</code>
📋 ${MSG}
💰 Top up your PEAQ balance immediately!
🕐 $(now_utc) | $(now_local)"
      fi
      ;;
    LOW_GAS|TX_UNDERPRICED)
      REPORT_LINES="${REPORT_LINES}🟡 <code>${LICENSE}</code> — ${CODE} (transient) | ${MSG}\n"
      if ! is_in_cooldown "$LICENSE" "$CODE"; then
        set_cooldown "$LICENSE" "$CODE"
        update_health_score "$LICENSE" "-3"
        send_telegram "🟡 <b>NodePulse Guard — Gas Issue</b>
🔑 License: <code>${LICENSE}</code>
📋 ${MSG}
🕐 $(now_utc) | $(now_local)
<i>Transient — usually self-resolves</i>"
      fi
      ;;
    NO_LOG)
      REPORT_LINES="${REPORT_LINES}⚪ <code>${LICENSE}</code> — No log yet\n"
      ;;
  esac
done

# ── Hourly report ─────────────────────────────────────────────
NOW_TS=$(date +%s)
LAST_REPORT=0; [ -f "$LAST_REPORT_FILE" ] && LAST_REPORT=$(cat "$LAST_REPORT_FILE")
if [ $(( NOW_TS - LAST_REPORT )) -ge 3600 ]; then
  date +%s > "$LAST_REPORT_FILE"
  HEALTH_LINES=""
  for LICENSE in "${LICENSES[@]}"; do
    S=$(get_health_score "$LICENSE")
    I="🟢"; [ "$S" -lt 80 ] && I="🟡"; [ "$S" -lt 50 ] && I="🔴"
    HEALTH_LINES="${HEALTH_LINES}${I} <code>${LICENSE}</code> — <b>${S}/100</b>\n"
  done
  STATUS_ICON="✅"; STATUS_MSG="All Clear"
  [ "$ALL_HEALTHY" -eq 0 ] && STATUS_ICON="⚠️" && STATUS_MSG="Issues Detected"
  send_telegram "${STATUS_ICON} <b>NodePulse Guard — ${STATUS_MSG}</b>
🕐 $(now_utc) | $(now_local)
📍 Host: $(hostname)

<b>Node Status:</b>
$(echo -e "$REPORT_LINES")
<b>Health Scores:</b>
$(echo -e "$HEALTH_LINES")"
fi

log "Guard run complete. Issues: $ISSUES"
log "=========================================="
