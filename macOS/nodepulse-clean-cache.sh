#!/bin/bash
# nodepulse-clean-cache.sh - NodePulse macOS Cache Cleaner

clean_dir() {
    if [[ -d "$1" ]]; then
        rm -rf "$1"/* "$1"/.* 2>/dev/null
        echo "→ $1"
    fi
}

echo "========================================"
echo " NodePulse macOS Cache Cleaner"
echo "========================================"
START_TIME=$(date +%s)
echo ""

# System caches
clean_dir "/tmp"
clean_dir "/Library/Caches"
sudo rm -rf /Library/Logs/* 2>/dev/null && echo "→ /Library/Logs"

# /var/folders requires glob expansion — cannot pass glob to function
for d in /var/folders/*/*/C; do
    [[ -d "$d" ]] && rm -rf "$d"/* 2>/dev/null && echo "→ $d"
done

# User caches
clean_dir "$HOME/Library/Caches"
clean_dir "$HOME/Library/Logs"
clean_dir "$HOME/Library/Saved Application State"
clean_dir "$HOME/Library/Cookies"

# Browser caches
clean_dir "$HOME/Library/Caches/Google/Chrome"
clean_dir "$HOME/Library/Caches/com.apple.Safari"
clean_dir "$HOME/Library/Caches/com.microsoft.Edge"

# Firefox — requires glob expansion
for d in "$HOME/Library/Application Support/Firefox/Profiles"/*/cache2; do
    [[ -d "$d" ]] && rm -rf "$d"/* 2>/dev/null && echo "→ $d"
done

# Teams
clean_dir "$HOME/Library/Application Support/Microsoft/Teams"

# Trash
rm -rf ~/.Trash/* 2>/dev/null && echo "→ ~/.Trash"

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo "✅ Cleanup complete! ⏱️ ${DURATION}s"
