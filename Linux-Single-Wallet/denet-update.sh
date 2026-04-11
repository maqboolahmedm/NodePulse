<<<<<<< HEAD
#!/bin/bash

# ============================================================
# DeNet Node Updater Script
# User: maqbool | Ubuntu VM
# Usage:
#   denet-update rc12        → Download & install v4.x.x-rc12
#   denet-update rc13        → Download & install v4.x.x-rc13
#   denet-update latest      → Auto-detect and install latest release
#   denet-update --check     → Just show what's available, don't install
# ============================================================

# --- Config ---
TELEGRAM_BOT_TOKEN="YOUR_TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="YOUR_TELEGRAM_CHAT_ID"
DENODE_BIN="/usr/bin/denode"
WALLET_ADDRESS="YOUR_WALLET_ADDRESS"
LICENSES=(YOUR_LICENSE_1 YOUR_LICENSE_2 YOUR_LICENSE_3)  # Add all your license numbers
NODE_LOG_DIR="$HOME/.denode/logs"
DOWNLOAD_DIR="$HOME/DeNet/updates"
GITHUB_API="https://api.github.com/repos/DeNetPRO/Node/releases"
GITHUB_RELEASES="https://github.com/DeNetPRO/Node/releases"

mkdir -p "$DOWNLOAD_DIR"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ============================================================
# Helper Functions
# ============================================================

now_utc() { date -u '+%Y-%m-%d %H:%M:%S UTC'; }
now_ist() { TZ='Asia/Kolkata' date '+%H:%M:%S IST'; }

log()     { echo -e "${CYAN}[$(now_utc)]${NC} $1"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warn()    { echo -e "${YELLOW}⚠️  $1${NC}"; }
error()   { echo -e "${RED}❌ $1${NC}"; }
info()    { echo -e "${BLUE}ℹ️  $1${NC}"; }

send_telegram() {
  local MESSAGE="$1"
  curl -s --max-time 15 -X POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    -d text="${MESSAGE}" \
    -d parse_mode="HTML" > /dev/null 2>&1
}

# ============================================================
# Step 1 — Resolve the target release from GitHub API
# ============================================================

resolve_release() {
  local INPUT="$1"   # e.g. "rc12", "rc13", "latest"
  local ALL_RELEASES

  log "Fetching release list from GitHub..."
  ALL_RELEASES=$(curl -s --max-time 20 "$GITHUB_API" 2>/dev/null)

  if [ -z "$ALL_RELEASES" ] || echo "$ALL_RELEASES" | grep -q '"message"'; then
    error "Could not reach GitHub API. Check your internet connection."
    exit 1
  fi

  if [ "$INPUT" = "latest" ]; then
    # Pick the first (most recent) release
    RELEASE_TAG=$(echo "$ALL_RELEASES" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if data:
    print(data[0]['tag_name'])
" 2>/dev/null)
  else
    # Match the rc number — e.g. "rc12" matches "v4.0.1-rc12"
    local RC_NUM="${INPUT,,}"   # lowercase
    RELEASE_TAG=$(echo "$ALL_RELEASES" | python3 -c "
import json, sys
data = json.load(sys.stdin)
target = '${RC_NUM}'
for release in data:
    tag = release['tag_name'].lower()
    if target in tag:
        print(release['tag_name'])
        break
" 2>/dev/null)
  fi

  if [ -z "$RELEASE_TAG" ]; then
    error "No release found matching '${INPUT}'."
    echo ""
    info "Available releases:"
    echo "$ALL_RELEASES" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for r in data[:10]:
    print('  •', r['tag_name'])
" 2>/dev/null
    echo ""
    info "Check manually: $GITHUB_RELEASES"
    exit 1
  fi

  echo "$RELEASE_TAG"
}

# ============================================================
# Step 2 — Find the Ubuntu/Linux AMD64 download URL
# ============================================================

find_download_url() {
  local TAG="$1"
  local RELEASE_DATA

  log "Fetching release details for ${TAG}..."
  RELEASE_DATA=$(curl -s --max-time 20 "${GITHUB_API}/tags/${TAG}" 2>/dev/null)

  # Try: denode-linux-amd64, denode_linux_amd64, denode-amd64-linux, etc.
  DOWNLOAD_URL=$(echo "$RELEASE_DATA" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assets = data.get('assets', [])
priority = [
    'denode-linux-amd64',
    'denode_linux_amd64',
    'denode-amd64',
    'denode-linux',
]
# First try exact priority matches
for p in priority:
    for a in assets:
        name = a['name'].lower()
        if p in name and 'deb' not in name and 'rpm' not in name:
            print(a['browser_download_url'])
            sys.exit(0)
# Fallback: any linux + amd64 asset
for a in assets:
    name = a['name'].lower()
    if 'linux' in name and ('amd64' in name or 'x86_64' in name):
        print(a['browser_download_url'])
        sys.exit(0)
# Last resort: .deb for Ubuntu
for a in assets:
    name = a['name'].lower()
    if '.deb' in name and ('amd64' in name or 'x86_64' in name):
        print(a['browser_download_url'])
        sys.exit(0)
" 2>/dev/null)

  if [ -z "$DOWNLOAD_URL" ]; then
    # Show all available assets so user can choose
    error "Could not find a Linux AMD64 binary in release ${TAG}."
    echo ""
    info "Available assets in this release:"
    echo "$RELEASE_DATA" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for a in data.get('assets', []):
    print('  •', a['name'])
    print('    URL:', a['browser_download_url'])
" 2>/dev/null
    echo ""
    info "Please check: ${GITHUB_RELEASES}/tag/${TAG}"
    exit 1
  fi

  echo "$DOWNLOAD_URL"
}

# ============================================================
# Step 3 — Show release info and confirm
# ============================================================

show_release_info() {
  local TAG="$1"
  local URL="$2"
  local CURRENT_VERSION

  CURRENT_VERSION=$("$DENODE_BIN" --version 2>/dev/null | head -1 || echo "unknown")

  echo ""
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}  DeNet Node Updater${NC}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${CYAN}Current version:${NC}  ${CURRENT_VERSION}"
  echo -e "  ${GREEN}Target release:${NC}   ${TAG}"
  echo -e "  ${BLUE}Download URL:${NC}     ${URL}"
  echo -e "  ${YELLOW}Binary path:${NC}      ${DENODE_BIN}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  warn "This will STOP all 6 nodes and replace the binary."
  warn "Each node restart costs a PEAQ transaction fee."
  echo ""
}

# ============================================================
# Step 4 — Download the binary
# ============================================================

download_binary() {
  local URL="$1"
  local TAG="$2"
  local FILENAME
  FILENAME=$(basename "$URL")
  local DEST="$DOWNLOAD_DIR/${FILENAME}"

  log "Downloading ${FILENAME}..."
  if curl -L --max-time 120 --progress-bar -o "$DEST" "$URL"; then
    success "Downloaded to ${DEST}"
  else
    error "Download failed!"
    exit 1
  fi

  # If it's a .deb file, extract the binary
  if echo "$FILENAME" | grep -q '\.deb$'; then
    log "Detected .deb package — extracting binary..."
    local EXTRACT_DIR="$DOWNLOAD_DIR/extract_${TAG}"
    mkdir -p "$EXTRACT_DIR"
    dpkg-deb -x "$DEST" "$EXTRACT_DIR" 2>/dev/null
    local EXTRACTED_BIN
    EXTRACTED_BIN=$(find "$EXTRACT_DIR" -name "denode" -type f 2>/dev/null | head -1)
    if [ -n "$EXTRACTED_BIN" ]; then
      DEST="$EXTRACTED_BIN"
      success "Extracted binary: ${DEST}"
    else
      error "Could not find denode binary inside .deb package."
      exit 1
    fi
  fi

  echo "$DEST"
}

# ============================================================
# Step 5 — Stop all nodes
# ============================================================

stop_all_nodes() {
  log "Stopping all DeNet nodes..."
  local STOPPED=0

  for LICENSE in "${LICENSES[@]}"; do
    local PID
    PID=$(ps aux | grep -v grep | grep "/usr/bin/denode" | grep -- "--license $LICENSE" | awk '{print $2}' | head -n 1)
    if [ -n "$PID" ]; then
      kill "$PID" 2>/dev/null
      STOPPED=$((STOPPED + 1))
      log "  Stopped node $LICENSE (PID: $PID)"
    else
      warn "  Node $LICENSE was not running."
    fi
  done

  sleep 3

  # Verify all stopped
  local STILL_RUNNING
  STILL_RUNNING=$(ps aux | grep -v grep | grep "/usr/bin/denode" | grep -v "denode-manager" | wc -l)
  if [ "$STILL_RUNNING" -gt 0 ]; then
    warn "Some processes still running — force killing..."
    pkill -9 -f "/usr/bin/denode --address" 2>/dev/null
    sleep 2
  fi

  success "All nodes stopped (${STOPPED} were running)."
}

# ============================================================
# Step 6 — Backup old binary and install new one
# ============================================================

install_binary() {
  local NEW_BIN="$1"
  local TAG="$2"
  local BACKUP_PATH="${DENODE_BIN}.backup-$(date +%Y%m%d-%H%M%S)"

  # Backup existing binary
  if [ -f "$DENODE_BIN" ]; then
    sudo cp "$DENODE_BIN" "$BACKUP_PATH"
    success "Old binary backed up to: ${BACKUP_PATH}"
  fi

  # Install new binary
  log "Installing new binary to ${DENODE_BIN}..."
  sudo cp "$NEW_BIN" "$DENODE_BIN"
  sudo chmod +x "$DENODE_BIN"

  # Verify installation
  local NEW_VERSION
  NEW_VERSION=$("$DENODE_BIN" --version 2>/dev/null | head -1 || echo "could not determine")
  success "New binary installed!"
  echo -e "  ${GREEN}Version:${NC} ${NEW_VERSION}"

  echo "$NEW_VERSION"
}

# ============================================================
# Step 7 — Check config for RC12 changes
# ============================================================

check_rc12_notes() {
  local TAG="$1"
  local RC_NUM
  RC_NUM=$(echo "$TAG" | grep -oP 'rc\d+' | grep -oP '\d+')

  if [ -n "$RC_NUM" ] && [ "$RC_NUM" -ge 12 ]; then
    echo ""
    echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${YELLOW}  RC12+ Checklist (from your session notes)${NC}"
    echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${CYAN}1.${NC} Run: ${GREEN}denode --help${NC}"
    echo -e "     → Check if ${YELLOW}--rpc${NC} flag is now available"
    echo -e "     → If yes, DeNet's own RPC is live — Onfinality keys may no longer be needed"
    echo ""
    echo -e "  ${CYAN}2.${NC} Check ${GREEN}~/.denode/manager_config.yaml${NC}"
    echo -e "     → See if RPC endpoints auto-updated to DeNet's own RPC"
    echo ""
    echo -e "  ${CYAN}3.${NC} Check monitor script: ${GREEN}~/DeNet/denet-monitor.sh${NC}"
    echo -e "     → Verify DENODE_BIN still points to /usr/bin/denode"
    echo -e "     → Check if log file naming changed (license-XXXX.log)"
    echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
  fi
}

# ============================================================
# --check mode: just list releases, don't install
# ============================================================

check_mode() {
  log "Fetching latest releases from GitHub..."
  local ALL_RELEASES
  ALL_RELEASES=$(curl -s --max-time 20 "$GITHUB_API" 2>/dev/null)

  if [ -z "$ALL_RELEASES" ]; then
    error "Could not reach GitHub. Check internet connection."
    exit 1
  fi

  local CURRENT_VERSION
  CURRENT_VERSION=$("$DENODE_BIN" --version 2>/dev/null | head -1 || echo "unknown")

  echo ""
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}  DeNet Available Releases${NC}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${CYAN}Currently installed:${NC} ${CURRENT_VERSION}"
  echo ""
  echo -e "  ${GREEN}Latest 10 releases:${NC}"
  echo "$ALL_RELEASES" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for r in data[:10]:
    tag = r['tag_name']
    date = r['published_at'][:10]
    pre = ' (pre-release)' if r.get('prerelease') else ''
    print(f'  • {tag}  [{date}]{pre}')
" 2>/dev/null
  echo ""
  echo -e "  ${BLUE}To install:${NC} denet-update rc12"
  echo -e "  ${BLUE}Latest:${NC}    denet-update latest"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  exit 0
}

# ============================================================
# Main
# ============================================================

INPUT="$1"

if [ -z "$INPUT" ]; then
  echo -e "${BOLD}Usage:${NC}"
  echo "  denet-update rc12        → Install rc12"
  echo "  denet-update rc13        → Install rc13"
  echo "  denet-update latest      → Install latest release"
  echo "  denet-update --check     → List available releases"
  exit 0
fi

if [ "$INPUT" = "--check" ] || [ "$INPUT" = "-c" ]; then
  check_mode
fi

echo ""
log "========== DeNet Update Started =========="

# Resolve release tag
RELEASE_TAG=$(resolve_release "$INPUT")
success "Found release: ${RELEASE_TAG}"

# Find download URL
DOWNLOAD_URL=$(find_download_url "$RELEASE_TAG")
success "Found download: $(basename $DOWNLOAD_URL)"

# Show info and confirm
show_release_info "$RELEASE_TAG" "$DOWNLOAD_URL"

# Confirm prompt
read -r -p "$(echo -e ${BOLD})Proceed with update? [yes/no]: $(echo -e ${NC})" CONFIRM
if [ "$CONFIRM" != "yes" ] && [ "$CONFIRM" != "y" ]; then
  warn "Update cancelled."
  exit 0
fi

echo ""
send_telegram "🔄 <b>DeNet Update Started</b>
📦 Target Release: <code>${RELEASE_TAG}</code>
🕐 $(now_utc) | $(now_ist)
📍 Host: $(hostname)

<i>Stopping nodes and installing new binary...</i>"

# Download
DOWNLOADED_BIN=$(download_binary "$DOWNLOAD_URL" "$RELEASE_TAG")

# Stop nodes
stop_all_nodes

# Install
NEW_VERSION=$(install_binary "$DOWNLOADED_BIN" "$RELEASE_TAG")

# RC12+ checklist
check_rc12_notes "$RELEASE_TAG"

# Final summary
echo ""
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${GREEN}  Update Complete!${NC}"
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${CYAN}Installed:${NC} ${NEW_VERSION}"
echo -e "  ${YELLOW}⚠️  Nodes are STOPPED. Start them manually:${NC}"
echo ""
echo -e "  ${GREEN}export DENODE_PASSWORD=\"YOUR_NODE_PASSWORD\"${NC}"
echo -e "  ${GREEN}bash ~/DeNet/denet-monitor.sh${NC}"
echo ""
echo -e "  Or via Telegram bot: ${CYAN}/restartall${NC}"
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

send_telegram "✅ <b>DeNet Update Complete!</b>
📦 Installed: <code>${RELEASE_TAG}</code>
🔢 Version: <code>${NEW_VERSION}</code>
🕐 $(now_utc) | $(now_ist)
📍 Host: $(hostname)

⚠️ <b>All 6 nodes are stopped.</b>
Use /restartall in the bot to restart all nodes, or run the monitor script manually.

$([ "$(echo "$RELEASE_TAG" | grep -oP 'rc\d+' | grep -oP '\d+')" -ge "12" ] && echo "💡 RC12+: Check if DeNet RPC is now available — run: denode --help")"

log "========== DeNet Update Finished =========="
=======

>>>>>>> ea719db645f5f3824483919fc75481022eac4da8
