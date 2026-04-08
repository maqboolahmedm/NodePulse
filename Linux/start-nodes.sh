#!/bin/bash

# ============================================================
# DeNet Node Starter Script
# User: maqbool | Ubuntu VM
# Simple script to start all 6 nodes manually
# Usage: bash start-nodes.sh
# ============================================================

DENODE_BIN="/usr/bin/denode"
WALLET_ADDRESS="YOUR_WALLET_ADDRESS"
LICENSES=(YOUR_LICENSE_1 YOUR_LICENSE_2 YOUR_LICENSE_3)
NODE_LOG_DIR="$HOME/.denode/logs"

mkdir -p "$NODE_LOG_DIR"

# ── Colours ──
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  DeNet Node Starter${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check password is exported
if [ -z "$DENODE_PASSWORD" ]; then
  echo -e "${RED}❌ DENODE_PASSWORD not set!${NC}"
  echo -e "${YELLOW}Run first: export DENODE_PASSWORD=\"YOUR_NODE_PASSWORD\"${NC}"
  exit 1
fi

# Check binary exists
if [ ! -f "$DENODE_BIN" ]; then
  echo -e "${RED}❌ denode binary not found at $DENODE_BIN${NC}"
  exit 1
fi

# Check storage drives
echo -e "${CYAN}Checking storage drives...${NC}"
ALL_MOUNTED=1
for LICENSE in "${LICENSES[@]}"; do
  DRIVE="/mnt/Denet-Storage/${LICENSE}"
  if [ -d "$DRIVE" ]; then
    echo -e "  ${GREEN}✅ ${DRIVE}${NC}"
  else
    echo -e "  ${RED}❌ ${DRIVE} — NOT FOUND${NC}"
    ALL_MOUNTED=0
  fi
done

if [ "$ALL_MOUNTED" -eq 0 ]; then
  echo ""
  echo -e "${RED}⚠️  Some drives missing! Check NAS is online.${NC}"
  read -p "Continue anyway? [y/N]: " CONT
  [ "$CONT" != "y" ] && [ "$CONT" != "Y" ] && exit 1
fi

echo ""
echo -e "${CYAN}Starting nodes...${NC}"
echo ""

SUCCESS=0
FAILED=0

for LICENSE in "${LICENSES[@]}"; do

  # Check if already running
  if ps aux | grep -v grep | grep "$DENODE_BIN" | grep -q -- "--license $LICENSE"; then
    PID=$(ps aux | grep -v grep | grep "$DENODE_BIN" | grep -- "--license $LICENSE" | awk '{print $2}')
    echo -e "  ${YELLOW}⚠️  Node ${LICENSE} already running (PID: ${PID}) — skipping${NC}"
    SUCCESS=$((SUCCESS + 1))
    continue
  fi

  # Start node
  nohup "$DENODE_BIN" \
    --address "$WALLET_ADDRESS" \
    --license "$LICENSE" \
    >> "$NODE_LOG_DIR/node-${LICENSE}.log" 2>&1 &

  sleep 2

  # Verify started
  if ps aux | grep -v grep | grep "$DENODE_BIN" | grep -q -- "--license $LICENSE"; then
    PID=$(ps aux | grep -v grep | grep "$DENODE_BIN" | grep -- "--license $LICENSE" | awk '{print $2}')
    echo -e "  ${GREEN}✅ Node ${LICENSE} started (PID: ${PID})${NC}"
    SUCCESS=$((SUCCESS + 1))
  else
    echo -e "  ${RED}❌ Node ${LICENSE} FAILED to start${NC}"
    FAILED=$((FAILED + 1))
  fi

done

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ "$FAILED" -eq 0 ]; then
  echo -e "${GREEN}${BOLD}  ✅ All ${SUCCESS} nodes started successfully!${NC}"
else
  echo -e "${YELLOW}${BOLD}  ⚠️  ${SUCCESS} started, ${FAILED} failed${NC}"
fi
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "Check status: ${CYAN}ps aux | grep denode | grep -v grep${NC}"
echo ""
