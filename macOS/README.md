# 🍎 NodePulse — macOS

> Status: 🔜 Coming Soon — Template available, community testing needed.

## Schedule with launchd

Create `~/Library/LaunchAgents/com.nodepulse.monitor.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.nodepulse.monitor</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/Users/YOUR_USERNAME/NodePulse/nodepulse-monitor.sh</string>
  </array>
  <key>StartInterval</key>
  <integer>300</integer>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
```

Load it:
```bash
launchctl load ~/Library/LaunchAgents/com.nodepulse.monitor.plist
```

## Help Wanted 🙏
Test and open a GitHub issue with results!
