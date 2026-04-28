# 🐧 NodePulse — Linux Multi Wallet

> For Datakeepers running **2–4 wallets** with different passwords.

## Files

Same as Linux-Single-Wallet — `nodepulse-monitor.sh` and `nodepulse-bot-listener.sh` support multiple wallets.

## Configuration

```bash
# Wallet 1
WALLET_1_ADDRESS="0x..."
WALLET_1_PASSWORD="your_password_1"
WALLET_1_LICENSES=(LICENSE_1 LICENSE_2 LICENSE_3)

# Wallet 2
WALLET_2_ADDRESS="0x..."
WALLET_2_PASSWORD="your_password_2"
WALLET_2_LICENSES=(LICENSE_4 LICENSE_5 LICENSE_6)

# Wallet 3 & 4 — leave empty if not used
WALLET_3_ADDRESS=""
WALLET_3_LICENSES=()
```

## Quick Start

```bash
git clone https://github.com/maqboolahmedm/NodePulse.git
cd NodePulse/Linux-Multi-Wallet

# Set Telegram credentials in all files
find . -name "nodepulse-*" -exec sed -i \
  's|YOUR_TELEGRAM_BOT_TOKEN|YOUR_ACTUAL_TOKEN|g;
   s|YOUR_TELEGRAM_CHAT_ID|YOUR_ACTUAL_CHAT_ID|g' {} +

# Fill wallet details
nano nodepulse-monitor.sh
bash nodepulse-setup.sh
```

## Telegram Output
Nodes grouped by wallet label (W1, W2, W3, W4) in all messages.
