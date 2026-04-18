#!/bin/bash

# ============================================================
# DeNet Node Updater — NodePulse v2.0
# Usage:
#   denet-update rc13        → Install rc13
#   denet-update rc14        → Install rc14
#   denet-update latest      → Install latest release
#   denet-update --check     → List available releases
# ============================================================

# --- Telegram Config ---
TELEGRAM_BOT_TOKEN="YOUR_TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="YOUR_TELEGRAM_CHAT_ID"

# --- Node Config ---
DENODE_BIN="/usr/bin/denode"
WALLET_ADDRESS="YOUR_WALLET_ADDRESS"
DENODE_PASSWORD="YOUR_NODE_PASSWORD"
LICENSES=(YOUR_W1_LICENSE_1 YOUR_W1_LICENSE_2 YOUR_W2_LICENSE_1 YOUR_W2_LICENSE_2)

# --- Paths ---
DENODE_DIR="$HOME/.denode"
NODE_LOG_DIR="$HOME/.denode/logs"
DOWNLOAD_DIR="$HOME/DeNet/updates"
GITHUB_API="https://api.github.com/repos/DeNetPRO/Node/releases"

# --- Timezone ---
LOCAL_TIMEZONE="YOUR_TIMEZONE"

mkdir -p "$DOWNLOAD_DIR"

# ============================================================
# Helpers
# ============================================================
now_utc()   { date -u '+%Y-%m-%d %H:%M:%S UTC'; }
now_local() { TZ="${LOCAL_TIMEZONE}" date '+%H:%M:%S %Z'; }

log()     { echo "[$(now_utc) | $(now_local)] $1"; }
success() { echo "✅ $1"; }
warn()    { echo "⚠️  $1"; }
error()   { echo "❌ $1"; }

send_telegram() {
  curl -s --max-time 15 -X POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    -d text="${1}" \
    -d parse_mode="HTML" > /dev/null 2>&1
}

# ============================================================
# Step 1 — Resolve release tag from input
# ============================================================
resolve_release() {
  local INPUT="$1"

  # If input looks like a tag already (e.g. v4.0.1-rc13)
  if echo "$INPUT" | grep -qP '^v\d+'; then
    echo "$INPUT"; return
  fi

  log "Fetching releases from GitHub..."
  local ALL_RELEASES
  ALL_RELEASES=$(curl -s --max-time 20 "$GITHUB_API" 2>/dev/null)

  if [ -z "$ALL_RELEASES" ]; then
    error "Could not reach GitHub. Check internet connection."
    exit 1
  fi

  if [ "$INPUT" = "latest" ]; then
    echo "$ALL_RELEASES" | python3 -c "
import json,sys
data=json.load(sys.stdin)
for r in data:
    if not r.get('draft'):
        print(r['tag_name']); break
" 2>/dev/null
  else
    # Match rc number e.g. rc13
    echo "$ALL_RELEASES" | python3 -c "
import json,sys
data=json.load(sys.stdin)
inp='${INPUT}'.lower()
for r in data:
    tag=r['tag_name'].lower()
    if inp in tag:
        print(r['tag_name']); break
" 2>/dev/null
  fi
}

# ============================================================
# Step 2 — Find .deb download URL
# ============================================================
find_download_url() {
  local TAG="$1"
  local RELEASE_DATA
  RELEASE_DATA=$(curl -s --max-time 20 \
    "https://api.github.com/repos/DeNetPRO/Node/releases/tags/${TAG}" 2>/dev/null)

  echo "$RELEASE_DATA" | python3 -c "
import json,sys
data=json.load(sys.stdin)
assets=data.get('assets',[])
# Prefer .deb for Linux
for a in assets:
    name=a['name'].lower()
    if 'linux' in name and 'amd64' in name and name.endswith('.deb'):
        print(a['browser_download_url']); exit()
# Fallback: any amd64 binary
for a in assets:
    name=a['name'].lower()
    if 'linux' in name and 'amd64' in name:
        print(a['browser_download_url']); exit()
# Fallback: any linux binary
for a in assets:
    name=a['name'].lower()
    if 'linux' in name:
        print(a['browser_download_url']); exit()
print('')
" 2>/dev/null
}

# ============================================================
# Step 3 — Show release info and confirm
# ============================================================
show_release_info() {
  local TAG="$1"
  local URL="$2"
  local CURRENT
  CURRENT=$("$DENODE_BIN" --version 2>/dev/null | head -1 || echo "unknown")

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  DeNet Node Updater"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Current : $CURRENT"
  echo "  Target  : $TAG"
  echo "  Package : $(basename $URL)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  warn "This will:"
  echo "  1. Stop all ${#LICENSES[@]} nodes"
  echo "  2. Delete ~/.denode folder (fresh start)"
  echo "  3. Install new binary"
  echo "  4. Restart all nodes"
  echo ""
}

# ============================================================
# Step 4 — Download binary
# ============================================================
download_binary() {
  local URL="$1"
  local TAG="$2"
  local FILENAME
  FILENAME=$(basename "$URL")
  local DEST="$DOWNLOAD_DIR/${FILENAME}"

  log "Downloading ${FILENAME}..."
  if curl -L --max-time 300 --progress-bar -o "$DEST" "$URL"; then
    success "Downloaded: ${DEST}"
  else
    error "Download failed!"
    exit 1
  fi
  echo "$DEST"
}

# ============================================================
# Step 5 — Stop all nodes
# ============================================================
stop_all_nodes() {
  log "Stopping all nodes..."
  local COUNT=0

  for LICENSE in "${LICENSES[@]}"; do
    local PID
    PID=$(ps aux | grep -v grep | grep "$DENODE_BIN" | \
          grep -- "--license $LICENSE" | awk '{print $2}' | head -1)
    if [ -n "$PID" ]; then
      kill "$PID" 2>/dev/null
      COUNT=$(( COUNT + 1 ))
      log "  Stopped node $LICENSE (PID: $PID)"
    fi
  done

  sleep 3

  # Force kill any remaining
  local REMAINING
  REMAINING=$(ps aux | grep -v grep | grep "$DENODE_BIN" | \
              grep -v "denode-manager" | wc -l)
  if [ "$REMAINING" -gt 0 ]; then
    warn "Force killing remaining processes..."
    pkill -9 -f "$DENODE_BIN" 2>/dev/null
    sleep 2
  fi

  success "All nodes stopped ($COUNT were running)"
}

# ============================================================
# Step 6 — Delete .denode folder
# ============================================================
delete_denode_folder() {
  log "Deleting ~/.denode folder..."
  if [ -d "$DENODE_DIR" ]; then
    rm -rf "$DENODE_DIR"
    success ".denode folder deleted — fresh start!"
  else
    warn ".denode folder not found — skipping"
  fi

  # Recreate empty logs folder
  mkdir -p "$NODE_LOG_DIR"
  success ".denode/logs recreated"
}

# ============================================================
# Step 7 — Install new binary
# ============================================================
install_binary() {
  local PACKAGE="$1"
  local FILENAME
  FILENAME=$(basename "$PACKAGE")

  log "Installing ${FILENAME}..."

  # Backup current binary
  local BACKUP="${DENODE_BIN}.backup-$(date +%Y%m%d-%H%M%S)"
  if [ -f "$DENODE_BIN" ]; then
    sudo cp "$DENODE_BIN" "$BACKUP"
    success "Old binary backed up: $BACKUP"
  fi

  # Install based on file type
  if echo "$FILENAME" | grep -q '\.deb$'; then
    # .deb package — install via dpkg
    log "Installing .deb package..."
    if sudo dpkg -i "$PACKAGE" 2>/dev/null; then
      success ".deb installed via dpkg"
    else
      # Extract binary manually from .deb
      log "dpkg failed — extracting binary manually..."
      local EXTRACT_DIR="$DOWNLOAD_DIR/extract"
      mkdir -p "$EXTRACT_DIR"
      dpkg-deb -x "$PACKAGE" "$EXTRACT_DIR" 2>/dev/null
      local EXTRACTED
      EXTRACTED=$(find "$EXTRACT_DIR" -name "denode" -type f 2>/dev/null | head -1)
      if [ -n "$EXTRACTED" ]; then
        sudo cp "$EXTRACTED" "$DENODE_BIN"
        sudo chmod +x "$DENODE_BIN"
        success "Binary extracted and installed manually"
      else
        error "Could not extract binary from .deb!"
        exit 1
      fi
    fi
  else
    # Raw binary
    sudo cp "$PACKAGE" "$DENODE_BIN"
    sudo chmod +x "$DENODE_BIN"
    success "Binary installed"
  fi

  # Verify
  local NEW_VERSION
  NEW_VERSION=$("$DENODE_BIN" --version 2>/dev/null | head -1 || echo "unknown")
  success "Installed version: $NEW_VERSION"
  echo "$NEW_VERSION"
}

# ============================================================
# Step 8 — Restart all nodes
# ============================================================
restart_all_nodes() {
  log "Restarting all nodes..."
  export DENODE_PASSWORD="$DENODE_PASSWORD"
  local COUNT=0

  for LICENSE in "${LICENSES[@]}"; do
    nohup "$DENODE_BIN" \
      --address "$WALLET_ADDRESS" \
      --license "$LICENSE" \
      >> "$NODE_LOG_DIR/node-${LICENSE}.log" 2>&1 &
    sleep 2

    local PID
    PID=$(ps aux | grep -v grep | grep "$DENODE_BIN" | \
          grep -- "--license $LICENSE" | awk '{print $2}' | head -1)
    if [ -n "$PID" ]; then
      success "Node $LICENSE started (PID: $PID)"
      COUNT=$(( COUNT + 1 ))
    else
      warn "Node $LICENSE failed to start!"
    fi
  done

  success "$COUNT/${#LICENSES[@]} nodes restarted"
  echo "$COUNT"
}

# ============================================================
# --check mode
# ============================================================
check_mode() {
  log "Fetching releases from GitHub..."
  local ALL_RELEASES
  ALL_RELEASES=$(curl -s --max-time 20 "$GITHUB_API" 2>/dev/null)

  if [ -z "$ALL_RELEASES" ]; then
    error "Could not reach GitHub."
    exit 1
  fi

  local CURRENT
  CURRENT=$("$DENODE_BIN" --version 2>/dev/null | head -1 || echo "unknown")

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  DeNet Available Releases"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Installed: $CURRENT"
  echo ""
  echo "  Latest releases:"
  echo "$ALL_RELEASES" | python3 -c "
import json,sys
data=json.load(sys.stdin)
for r in data[:10]:
    tag=r['tag_name']
    date=r['published_at'][:10]
    pre=' (pre-release)' if r.get('prerelease') else ''
    print(f'  • {tag}  [{date}]{pre}')
" 2>/dev/null
  echo ""
  echo "  Usage: denet-update rc14"
  echo "         denet-update latest"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  exit 0
}

# ============================================================
# Main
# ============================================================
INPUT="$1"

if [ -z "$INPUT" ]; then
  echo ""
  echo "Usage:"
  echo "  denet-update rc14      → Install rc14"
  echo "  denet-update latest    → Install latest release"
  echo "  denet-update --check   → List available releases"
  echo ""
  exit 0
fi

[ "$INPUT" = "--check" ] || [ "$INPUT" = "-c" ] && check_mode

echo ""
log "========== DeNet Update Started =========="
log "Input: $INPUT"

# Resolve tag
RELEASE_TAG=$(resolve_release "$INPUT")
if [ -z "$RELEASE_TAG" ]; then
  error "Could not find release matching: $INPUT"
  exit 1
fi
success "Found release: $RELEASE_TAG"

# Find download URL
DOWNLOAD_URL=$(find_download_url "$RELEASE_TAG")
if [ -z "$DOWNLOAD_URL" ]; then
  error "No download URL found for: $RELEASE_TAG"
  echo "Check manually: https://github.com/DeNetPRO/Node/releases"
  exit 1
fi
success "Download URL found: $(basename $DOWNLOAD_URL)"

# Show info and confirm
show_release_info "$RELEASE_TAG" "$DOWNLOAD_URL"
read -r -p "Proceed with update? [yes/no]: " CONFIRM
if [ "$CONFIRM" != "yes" ] && [ "$CONFIRM" != "y" ]; then
  warn "Update cancelled."
  exit 0
fi

# Telegram — update started
send_telegram "🔄 <b>DeNet Update Started</b>
📦 Target: <code>${RELEASE_TAG}</code>
🕐 $(now_utc) | $(now_local)
📍 Host: $(hostname)

<i>Stopping nodes → Deleting .denode → Installing → Restarting...</i>"

# Execute steps
PACKAGE=$(download_binary "$DOWNLOAD_URL" "$RELEASE_TAG")
stop_all_nodes
delete_denode_folder
NEW_VERSION=$(install_binary "$PACKAGE")
STARTED=$(restart_all_nodes)

# Final summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Update Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Version : $NEW_VERSION"
echo "  Nodes   : $STARTED/${#LICENSES[@]} running"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Telegram — update complete
send_telegram "✅ <b>DeNet Update Complete!</b>
📦 Installed: <code>${NEW_VERSION}</code>
🔢 Nodes running: <b>${STARTED}/${#LICENSES[@]}</b>
🕐 $(now_utc) | $(now_local)
📍 Host: $(hostname)"

log "========== DeNet Update Finished =========="
