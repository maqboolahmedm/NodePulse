# nodepulse-clean-cache.ps1 - NodePulse Windows Cache Cleaner (Fixed)

Function Remove-CacheFiles {
    param([string]$path)
    try {
        if (Test-Path $path) {
            Remove-Item -Path $path -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Host "Skipped: $path" -ForegroundColor Yellow
    }
}

Function Clear-GlobalWindowsCache {
    Write-Host "→ System cache..." -ForegroundColor Gray
    Remove-CacheFiles 'C:\Windows\Temp'
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    Remove-CacheFiles 'C:\Windows\Prefetch'
}

Function Clear-UserCacheFiles {
    Write-Host "→ User cache..." -ForegroundColor Gray
    Remove-CacheFiles "$env:TEMP"
    Remove-CacheFiles "$env:USERPROFILE\AppData\Local\Temp"
    Remove-CacheFiles "$env:USERPROFILE\AppData\Local\Microsoft\Windows\INetCache"
    Remove-CacheFiles "$env:USERPROFILE\AppData\Local\Microsoft\Windows\INetCookies"
    Remove-CacheFiles "$env:USERPROFILE\AppData\Local\Microsoft\Windows\WER"
}

Function Clear-ChromeCache { 
    $p = "$env:USERPROFILE\AppData\Local\Google\Chrome\User Data\Default"
    if (Test-Path $p) { Write-Host "→ Chrome..." -ForegroundColor Gray; Remove-CacheFiles "$p\Cache*"; Remove-CacheFiles "$p\Cookies"; Remove-CacheFiles "$p\History" }
}

Function Clear-EdgeCache {
    $p = "$env:USERPROFILE\AppData\Local\Microsoft\Edge\User Data\Default"
    if (Test-Path $p) { Write-Host "→ Edge..." -ForegroundColor Gray; Remove-CacheFiles "$p\Cache*"; Remove-CacheFiles "$p\Cookies"; Remove-CacheFiles "$p\History" }
}

Function Clear-FirefoxCache {
    $profiles = "$env:USERPROFILE\AppData\Local\Mozilla\Firefox\Profiles"
    if (Test-Path $profiles) { Write-Host "→ Firefox..." -ForegroundColor Gray; Get-ChildItem $profiles | Where-Object { $_.Name -match 'default' } | ForEach-Object { Remove-CacheFiles "$($_.FullName)\cache2"; Remove-CacheFiles "$($_.FullName)\thumbnails" } }
}

Function Clear-TeamsCache {
    $p = "$env:USERPROFILE\AppData\Roaming\Microsoft\Teams"
    if (Test-Path $p) { Write-Host "→ Teams..." -ForegroundColor Gray; Remove-CacheFiles "$p\cache"; Remove-CacheFiles "$p\blob_storage"; Remove-CacheFiles "$p\databases"; Remove-CacheFiles "$p\gpucache" }
}

# MAIN - FIXED TIMING & NO PROMPTS
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "     NodePulse Cache Cleaner" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$StartTime = Get-Date  # ← FIXED: No space!
Clear-UserCacheFiles
Clear-GlobalWindowsCache
Clear-ChromeCache
Clear-EdgeCache
Clear-FirefoxCache
Clear-TeamsCache
$EndTime = Get-Date

Write-Host ""
Write-Host "✅ Cleanup complete!" -ForegroundColor Green
Write-Host "⏱️  $([math]::Round(($EndTime - $StartTime).TotalSeconds,1))s" -ForegroundColor Cyan