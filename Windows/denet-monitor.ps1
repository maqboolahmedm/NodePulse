# ============================================================
# DeNet Node Monitor & Auto-Restart Script — Windows
# NodePulse v2.0
# Template: Replace YOUR_XXX_HERE with your actual values
# Runs via Windows Task Scheduler (every 5 minutes)
# ============================================================

# --- Telegram Config ---
$TELEGRAM_BOT_TOKEN = "YOUR_TELEGRAM_BOT_TOKEN"
$TELEGRAM_CHAT_ID   = "YOUR_TELEGRAM_CHAT_ID"

# --- Node Config ---
$DENODE_BIN      = "C:\Program Files\DeNet\denode.exe"   # Adjust path
$WALLET_ADDRESS  = "YOUR_WALLET_ADDRESS"
$LICENSES        = @("YOUR_LICENSE_1", "YOUR_LICENSE_2")  # e.g. @("1072", "1864")
$DENODE_PASSWORD = "YOUR_NODE_PASSWORD"

# --- Timezone Config ---
# Your local timezone string e.g. "India Standard Time", "W. Europe Standard Time"
# Full list: https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/default-time-zones
$LOCAL_TIMEZONE = "YOUR_TIMEZONE"  # e.g. "India Standard Time"

# --- Paths ---
$NODE_LOG_DIR       = "$env:USERPROFILE\.denode\logs"
$LOG_FILE           = "$env:USERPROFILE\.denode\monitor.log"
$RESTART_FILE       = "$env:USERPROFILE\.denode\.restart_counts"
$PENALTY_FILE       = "$env:USERPROFILE\.denode\.node_penalties"
$PID_STATE_FILE     = "$env:USERPROFILE\.denode\.node_pids"
$LAST_SEEN_FILE     = "$env:USERPROFILE\.denode\.node_last_seen"
$DOWNTIME_LOG       = "$env:USERPROFILE\.denode\.node_downtime_log"
$HEARTBEAT_FILE     = "$env:USERPROFILE\.denode\.last_heartbeat"

# --- Penalty Config ---
$PENALTY_WARN     = 5
$PENALTY_CRITICAL = 8
$PENALTY_MAX      = 10

New-Item -ItemType Directory -Force -Path $NODE_LOG_DIR | Out-Null
$env:DENODE_PASSWORD = $DENODE_PASSWORD

# ============================================================
# Helper Functions
# ============================================================

function Get-NowUTC { return (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss UTC") }

function Get-NowLocal {
    try {
        $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById($LOCAL_TIMEZONE)
        $local = [System.TimeZoneInfo]::ConvertTimeFromUtc((Get-Date).ToUniversalTime(), $tz)
        $abbr = $tz.DisplayName -replace '.*\(','(' -replace '\).*',''
        return $local.ToString("HH:mm:ss") + " " + $LOCAL_TIMEZONE
    } catch {
        return (Get-Date).ToString("HH:mm:ss") + " Local"
    }
}

function Write-Log($Message) {
    $entry = "[$(Get-NowUTC) | $(Get-NowLocal)] $Message"
    Write-Host $entry
    Add-Content -Path $LOG_FILE -Value $entry
}

function Send-Telegram($Message) {
    try {
        $body = @{ chat_id = $TELEGRAM_CHAT_ID; text = $Message; parse_mode = "HTML" }
        Invoke-RestMethod -Uri "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" `
            -Method POST -Body ($body | ConvertTo-Json) -ContentType "application/json" | Out-Null
    } catch {
        Write-Log "Telegram error: $_"
    }
}

function Get-NodeProcess($License) {
    return Get-WmiObject Win32_Process -Filter "Name='denode.exe'" |
        Where-Object { $_.CommandLine -like "*--license $License*" }
}

# ============================================================
# PID Tracking
# ============================================================

function Get-SavedPid($License) {
    if (-not (Test-Path $PID_STATE_FILE)) { return "" }
    $line = Get-Content $PID_STATE_FILE | Where-Object { $_ -match "^${License}=" }
    if ($line) { return ($line -split "=")[1] } else { return "" }
}

function Save-Pid($License, $Pid) {
    if (Test-Path $PID_STATE_FILE) {
        $content = Get-Content $PID_STATE_FILE | Where-Object { $_ -notmatch "^${License}=" }
        Set-Content $PID_STATE_FILE $content
    }
    Add-Content $PID_STATE_FILE "${License}=${Pid}"
}

function Update-LastSeen($License) {
    $now = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if (Test-Path $LAST_SEEN_FILE) {
        $content = Get-Content $LAST_SEEN_FILE | Where-Object { $_ -notmatch "^${License}=" }
        Set-Content $LAST_SEEN_FILE $content
    }
    Add-Content $LAST_SEEN_FILE "${License}=${now}"
}

function Get-LastSeen($License) {
    if (-not (Test-Path $LAST_SEEN_FILE)) { return 0 }
    $line = Get-Content $LAST_SEEN_FILE | Where-Object { $_ -match "^${License}=" }
    if ($line) { return [int]($line -split "=")[1] } else { return 0 }
}

# ============================================================
# Restart & Penalty Counter
# ============================================================

function Get-RestartCount($License) {
    if (-not (Test-Path $RESTART_FILE)) { return 0 }
    $line = Get-Content $RESTART_FILE | Where-Object { $_ -match "^${License}=" }
    if ($line) { return [int]($line -split "=")[1] } else { return 0 }
}

function Increment-RestartCount($License) {
    $count = (Get-RestartCount $License) + 1
    if (Test-Path $RESTART_FILE) {
        $content = Get-Content $RESTART_FILE | Where-Object { $_ -notmatch "^${License}=" }
        Set-Content $RESTART_FILE $content
    }
    Add-Content $RESTART_FILE "${License}=${count}"
}

function Get-PenaltyCount($License) {
    if (-not (Test-Path $PENALTY_FILE)) { return 0 }
    $line = Get-Content $PENALTY_FILE | Where-Object { $_ -match "^${License}=" }
    if ($line) { return [int]($line -split "=")[1] } else { return 0 }
}

function Increment-Penalty($License) {
    $count = (Get-PenaltyCount $License) + 1
    if (Test-Path $PENALTY_FILE) {
        $content = Get-Content $PENALTY_FILE | Where-Object { $_ -notmatch "^${License}=" }
        Set-Content $PENALTY_FILE $content
    }
    Add-Content $PENALTY_FILE "${License}=${count}"
    return $count
}

function Reset-Penalty($License) {
    if (Test-Path $PENALTY_FILE) {
        $content = Get-Content $PENALTY_FILE | Where-Object { $_ -notmatch "^${License}=" }
        Set-Content $PENALTY_FILE $content
    }
    Add-Content $PENALTY_FILE "${License}=0"
}

# ============================================================
# Node Functions
# ============================================================

function Get-NodeUptime($License) {
    $proc = Get-NodeProcess $License
    if (-not $proc) { return "not running" }
    $startTime = (Get-Process -Id $proc.ProcessId -ErrorAction SilentlyContinue).StartTime
    if (-not $startTime) { return "unknown" }
    $uptime = (Get-Date) - $startTime
    $result = ""
    if ($uptime.Days -gt 0)    { $result += "$($uptime.Days)d " }
    if ($uptime.Hours -gt 0)   { $result += "$($uptime.Hours)h " }
    if ($uptime.Minutes -gt 0) { $result += "$($uptime.Minutes)m" }
    if ($result -eq "")        { $result = "< 1m" }
    return $result.Trim()
}

function Restart-DeNetNode($License) {
    # Get old PID — from live process first, then saved file
    $proc = Get-NodeProcess $License
    $oldPid = if ($proc) { $proc.ProcessId } else { Get-SavedPid $License }

    # Calculate downtime
    $lastSeen = Get-LastSeen $License
    $offlineDuration = "unknown"
    $wentDownUtc = "unknown"
    if ($lastSeen -gt 0) {
        $now = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $secs = $now - $lastSeen
        $h = [math]::Floor($secs / 3600)
        $m = [math]::Floor(($secs % 3600) / 60)
        $offlineDuration = if ($h -gt 0) { "${h}h ${m}m" } else { "${m}m" }
        $wentDownUtc = [DateTimeOffset]::FromUnixTimeSeconds($lastSeen).UtcDateTime.ToString("yyyy-MM-dd HH:mm:ss UTC")
    }

    Write-Log "Restarting node $License (last alive: $wentDownUtc, offline: $offlineDuration)..."

    # Kill if running
    if ($proc) { Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue; Start-Sleep 2 }

    # Start node
    $logPath = "$NODE_LOG_DIR\node-${License}.log"
    Start-Process -FilePath $DENODE_BIN `
        -ArgumentList "--address $WALLET_ADDRESS --license $License" `
        -RedirectStandardOutput $logPath -NoNewWindow

    Start-Sleep 4

    $newProc = Get-NodeProcess $License
    if ($newProc) {
        $newPid = $newProc.ProcessId
        Increment-RestartCount $License
        Save-Pid $License $newPid
        Update-LastSeen $License
        $total = Get-RestartCount $License

        # Log downtime
        Add-Content $DOWNTIME_LOG "${License}|$(Get-NowUTC)|${wentDownUtc}|${offlineDuration}|${oldPid}|${newPid}"

        Write-Log "Node $License restarted (PID: $newPid, offline: $offlineDuration, Total: $total)"
        Send-Telegram "✅ <b>DeNet Node Restarted</b>
🔑 License: <code>$License</code>
🆔 Old PID: <code>$oldPid</code> → New: <code>$newPid</code>
🔄 Total Restarts: <b>$total</b>
📅 Last alive: <b>$wentDownUtc</b>
⏱ Offline for: <b>$offlineDuration</b>
🕐 $(Get-NowUTC)
🕐 $(Get-NowLocal)
📍 Host: $env:COMPUTERNAME"
    } else {
        Write-Log "Node $License FAILED to restart!"
        Send-Telegram "❌ <b>Node $License FAILED to Restart</b>
⚠️ Manual intervention required!
📅 Last alive: <b>$wentDownUtc</b>
⏱ Offline: <b>$offlineDuration</b>
🕐 $(Get-NowUTC)
📍 Host: $env:COMPUTERNAME"
    }
}

# ============================================================
# Heartbeat
# ============================================================

function Should-SendHeartbeat {
    if (-not (Test-Path $HEARTBEAT_FILE)) { return $true }
    $last = [int](Get-Content $HEARTBEAT_FILE)
    $now  = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    return ($now - $last) -ge 3600
}

function Send-Heartbeat {
    $lines = ""
    foreach ($License in $LICENSES) {
        $proc = Get-NodeProcess $License
        if ($proc) {
            $pid   = $proc.ProcessId
            $up    = Get-NodeUptime $License
            $rc    = Get-RestartCount $License
            $pen   = Get-PenaltyCount $License
            $icon  = if ($pen -ge $PENALTY_CRITICAL) { "🟠" } elseif ($pen -gt 0) { "🟡" } else { "🟢" }
            $lines += "🟢 <code>$License</code> — PID <code>$pid</code> — Up: <b>$up</b> — Restarts: <b>$rc</b> — ${icon} Penalties: <b>$pen/$PENALTY_MAX</b>`n"
            Save-Pid $License $pid
            Update-LastSeen $License
        } else {
            $rc = Get-RestartCount $License
            $lines += "🔴 <code>$License</code> — DOWN — Restarts: <b>$rc</b>`n"
        }
    }
    Send-Telegram "💓 <b>DeNet Node Monitor HeartBeat</b>
📍 Host: $env:COMPUTERNAME
🕐 $(Get-NowUTC)
🕐 $(Get-NowLocal)

<b>Node Status:</b>
$lines"
    [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds() | Set-Content $HEARTBEAT_FILE
    Write-Log "Heartbeat sent."
}

# ============================================================
# Main
# ============================================================

Write-Log "========== DeNet Monitor Run Started =========="

$downCount = 0
foreach ($License in $LICENSES) {
    $proc = Get-NodeProcess $License
    if ($proc) {
        $pid  = $proc.ProcessId
        $up   = Get-NodeUptime $License
        Write-Log "Node $License running (PID: $pid, Uptime: $up)"
        # Save PID every run — ensures PID file is always fresh
        Save-Pid $License $pid
        Update-LastSeen $License
    } else {
        Write-Log "Node $License DOWN — restarting..."
        $downCount++
        Send-Telegram "⚠️ <b>DeNet Node Down Detected</b>
🔑 License: <code>$License</code>
🕐 $(Get-NowUTC)
📍 Host: $env:COMPUTERNAME"
        Restart-DeNetNode $License
    }
}

if ($downCount -eq 0) { Write-Log "All nodes running normally." }
else { Write-Log "$downCount node(s) restarted." }

if (Should-SendHeartbeat) { Send-Heartbeat }

Write-Log "========== DeNet Monitor Run Finished =========="
