#!/bin/bash
# nodepulse-clean-cache.sh - NodePulse macOS Cache Cleaner

clean_dir() {
    if [[ -d "$1" ]]; then
        rm -rf "$1"/* "$1"/.* 2>/dev/null
        echo "→ $1"
    fi
}

echo "========================================"
echo "     NodePulse macOS Cache Cleaner"
echo "========================================"

START_TIME=$(date +%s)
echo ""

# System caches
clean_dir "/tmp"
clean_dir "/var/folders/*/*/C"
clean_dir "/Library/Caches"
sudo rm -rf /Library/Logs/* 2>/dev/null

# User caches
clean_dir "$HOME/Library/Caches"
clean_dir "$HOME/Library/Logs"
clean_dir "$HOME/Library/Saved Application State"
clean_dir "$HOME/Library/Cookies"

# Browser caches
clean_dir "$HOME/Library/Caches/Google/Chrome"
clean_dir "$HOME/Library/Caches/com.apple.Safari"
clean_dir "$HOME/Library/Caches/com.microsoft.Edge"
clean_dir "$HOME/Library/Application Support/Firefox/Profiles/*/cache2"
clean_dir "$HOME/Library/Application Support/Microsoft/Teams"

# Trash
rm -rf ~/.Trash/* 2>/dev/null

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
echo ""
echo "✅ Cleanup complete! ⏱️ ${DURATION}s"