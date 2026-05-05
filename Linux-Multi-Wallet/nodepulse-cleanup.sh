#!/bin/bash

# ============================================================
# NodePulse Cleanup — RAM & Cache Release
# Clears system page cache, temp files, old logs
# Safe to run anytime — no data loss
# ============================================================

TELEGRAM_BOT_TOKEN="YOUR_TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="YOUR_TELEGRAM_CHAT_ID"
LOCAL_TIMEZONE="YOUR_TIMEZONE"
LOG_FILE="$HOME/.denode/cleanup.log"

now_utc()   { date -u '+%Y-%m-%d %H:%M:%S UTC'; }
now_local() { TZ="${LOCAL_TIMEZONE}" date '+%H:%M:%S %Z'; }

log() { echo "[$(now_utc) | $(now_local)] [CLEANUP] $1" | tee -a "$LOG_FILE"; }

send_telegram() {
  curl -s --max-time 15 -X POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    -d text="${1}" \
    -d parse_mode="HTML" > /dev/null 2>&1
}

log "Starting cleanup..."

# ── Before stats ─────────────────────────────────────────
MEM_BEFORE=$(free -m | awk '/^Mem:/{printf "%dMB used / %dMB total", $3, $2}')
DISK_BEFORE=$(df -h / | awk 'NR==2{print $3" used / "$2" total"}')

# ── 1. Sync filesystem buffers ───────────────────────────
log "Syncing filesystem..."
sync

# ── 2. Drop page cache, dentries, inodes ────────────────
log "Dropping page cache..."
echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
sleep 1

# ── 3. Clear systemd journal logs older than 7 days ─────
log "Clearing old journal logs..."
sudo journalctl --vacuum-time=7d --quiet 2>/dev/null

# ── 4. Clear apt cache ───────────────────────────────────
log "Clearing apt cache..."
sudo apt-get clean -y > /dev/null 2>&1

# ── 5. Clear thumbnail cache ─────────────────────────────
log "Clearing thumbnail cache..."
rm -rf ~/.cache/thumbnails/* 2>/dev/null

# ── 6. Clear temp files ──────────────────────────────────
log "Clearing temp files..."
sudo rm -rf /tmp/* 2>/dev/null
sudo rm -rf /var/tmp/* 2>/dev/null

# ── 7. Clear old NodePulse logs (keep last 500 lines) ────
log "Trimming NodePulse logs..."
for LOG in "$HOME"/.denode/logs/node-*.log; do
  [ -f "$LOG" ] || continue
  LINES=$(wc -l < "$LOG")
  if [ "$LINES" -gt 500 ]; then
    tail -500 "$LOG" > "${LOG}.tmp" && mv "${LOG}.tmp" "$LOG"
    log "  Trimmed $(basename $LOG): ${LINES} → 500 lines"
  fi
done

# ── 8. Clear guard/cleanup logs ──────────────────────────
for LOG in "$HOME"/.nodepulse_guard/guard.log \
           "$HOME"/.denode/nexus-ip-watch.log; do
  [ -f "$LOG" ] || continue
  LINES=$(wc -l < "$LOG")
  if [ "$LINES" -gt 300 ]; then
    tail -300 "$LOG" > "${LOG}.tmp" && mv "${LOG}.tmp" "$LOG"
  fi
done

# ── After stats ──────────────────────────────────────────
MEM_AFTER=$(free -m | awk '/^Mem:/{printf "%dMB used / %dMB total", $3, $2}')
DISK_AFTER=$(df -h / | awk 'NR==2{print $3" used / "$2" total"}')

MEM_FREED=$(( $(free -m | awk '/^Mem:/{print $3}') ))
MEM_BEFORE_MB=$(echo "$MEM_BEFORE" | grep -oP '^\d+')
MEM_FREED_MB=$(( MEM_BEFORE_MB - MEM_FREED ))

log "Cleanup complete!"
log "RAM: $MEM_BEFORE → $MEM_AFTER"
log "Disk: $DISK_BEFORE → $DISK_AFTER"

send_telegram "🧹 <b>NodePulse Cleanup Complete</b>
🕐 $(now_utc) | $(now_local)
📍 Host: $(hostname)

<b>RAM:</b>
  Before: ${MEM_BEFORE}
  After:  ${MEM_AFTER}
  Freed:  ~${MEM_FREED_MB}MB

<b>Disk:</b>
  Before: ${DISK_BEFORE}
  After:  ${DISK_AFTER}

✅ Page cache cleared
✅ Journal logs trimmed (7d)
✅ Apt cache cleared
✅ Temp files cleared
✅ Node logs trimmed (500 lines max)"
