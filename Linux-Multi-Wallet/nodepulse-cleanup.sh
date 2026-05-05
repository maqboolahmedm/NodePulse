#!/bin/bash
# nodepulse-cleanup.sh: Automates system cleanup
# Clear APT cache
sudo apt clean
sudo apt autoremove -y

# Clear system journals
sudo journalctl --vacuum-time=30d

# Clear thumbnail and trash caches
rm -rf ~/.cache/thumbnails/*
rm -rf ~/.local/share/Trash/*

# Clear system temp files older than 30 days
sudo find /tmp -type f -atime +7 -delete 2>/dev/null