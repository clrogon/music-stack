<#
.SYNOPSIS
    One-shot native setup of the music-stack (Navidrome + Lidarr + qBittorrent) on Windows.

.DESCRIPTION
    Idempotent. Requires Administrator. Reads settings.env, installs dependencies
    (ffmpeg, qBittorrent, Python), downloads Navidrome + Lidarr + NSSM, writes
    configs, registers auto-start services, and configures Lidarr via its API.

    Run from an elevated prompt:
      powershell -ExecutionPolicy Bypass -File scripts\windows\Setup-MusicStack.ps1
#>
[CmdletBinding()]
param(
    [string]$Settings = ""
)

$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------- helpers --
function Write-Log  { param([string]$m) Write-Host "[+] $m" -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host "[!] $m" -ForegroundColor Yellow }
function Write-Err  { param([string]$m) Write-Host "[x] $m" -ForegroundColor Red }

function Test-Admin {
    $p = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-Setting {
    param([string]$Key, [string]$Default = "")
    if (-not (Test-Path -LiteralPath $script:SettingsFile)) { return $Default }
    $line = Get-Content -LiteralPath $script:SettingsFile |
        Where-Object { $_ -match "^$([regex]::Escape($Key))=" } | Select-Object -First 1
    if (-not $line) { return $Default }
    $val = ($line -split '=', 2)[1]
    if ([string]::IsNullOrWhiteSpace($val)) { return $Default }
    return $val.Trim()
}

function Get-GithubLatestAsset {
    param([string]$Repo, [string]$Match)
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" `
        -Headers @{ 'User-Agent' = 'music-stack' }
    $asset = $rel.assets | Where-Object { $_.name -like $Match } | Select-Object -First 1
    if (-not $asset) { throw "no matching asset for $Match in $Repo release $($rel.tag_name)" }
    return @{ Tag = $rel.tag_name; Name = $asset.name; Url = $asset.browser_download_url }
}

function Remove-ServiceIfPresent {
    param([string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($svc) {
        Write-Log "Removing existing service '$Name' (will be re-registered)"
        Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
        sc.exe delete $Name | Out-Null
        Start-Sleep -Seconds 2
    }
}

# -------------------------------------------------------------- elevation --
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
if (-not $Settings) { $Settings = Join-Path $repoRoot 'settings.env' }
$script:SettingsFile = $Settings

if (-not (Test-Admin)) {
    Write-Warn "Elevating to Administrator..."
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($Settings) { $argList += @('-Settings', "`"$Settings`"") }
    Start-Process -Verb RunAs -FilePath 'powershell.exe' -ArgumentList $argList `
        -WorkingDirectory $PSScriptRoot
    exit
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Err "winget not found. Install App Installer from the Microsoft Store and retry."
    exit 1
}

# ---------------------------------------------------------------- settings --
$musicDir      = Get-Setting 'MUSIC_DIR' 'C:\Music'
$dataDir       = Get-Setting 'DATA_DIR' 'C:\ProgramData\music-stack'
$downloadDir   = Get-Setting 'DOWNLOAD_DIR' (Join-Path $dataDir 'downloads')
$ndPort        = Get-Setting 'NAVIDROME_PORT' '4533'
$lidarrPort    = Get-Setting 'LIDARR_PORT' '8686'
$qbitPort      = Get-Setting 'QBIT_PORT' '8080'
$qbitUser      = Get-Setting 'QBIT_USER' 'admin'
$qbitPassword  = Get-Setting 'QBIT_PASSWORD' ''
$lidarrKey     = Get-Setting 'LIDARR_API_KEY' ''
$scanSchedule  = Get-Setting 'NAVIDROME_SCAN_SCHEDULE' ''

if (-not $qbitPassword) {
    Write-Err "QBIT_PASSWORD is empty in $Settings. Set a qBittorrent WebUI password first."
    exit 1
}
if (-not $lidarrKey) {
    $lidarrKey = -join ((48..57) + (97..102) | Get-Random -Count 32 | ForEach-Object { [char]$_ })
    Write-Log "Generated Lidarr API key"
}

$ndHome = 'C:\Program Files\Navidrome'
$lidarrHome = 'C:\Program Files\Lidarr'
$ndData  = Join-Path $dataDir 'navidrome'
$lidarrData = Join-Path $dataDir 'lidarr'
$logs    = Join-Path $dataDir 'logs'
$nssmHome = 'C:\Program Files\NSSM'
$work    = Join-Path $env:TEMP 'music-stack-install'

# ------------------------------------------------------------- directories --
foreach ($d in @($musicDir, $downloadDir, $ndData, $lidarrData, $logs, $work)) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}
icacls.exe $musicDir /grant "SYSTEM:(OI)(CI)M" "$env:USERNAME:(OI)(CI)M" | Out-Null
icacls.exe $downloadDir /grant "SYSTEM:(OI)(CI)M" "$env:USERNAME:(OI)(CI)M" | Out-Null

# ------------------------------------------------------------- dependencies --
Write-Log "Installing ffmpeg via winget..."
winget install --id Gyan.FFmpeg -e --accept-source-agreements --accept-package-agreements --silent --disable-interactivity
if (-not $?) { Write-Warn "ffmpeg install may need attention; Navidrome requires it." }

Write-Log "Installing qBittorrent via winget..."
winget install --id qBittorrent.qBittorrent -e --accept-source-agreements --accept-package-agreements --silent --disable-interactivity
if (-not $?) { Write-Warn "qBittorrent install reported a problem; verify it installed." }

# Locate ffmpeg.exe from the winget package (Gyan.FFmpeg).
$ffmpeg = Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages') `
    -Recurse -Filter 'ffmpeg.exe' -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1
if (-not $ffmpeg) { Write-Warn "ffmpeg.exe not found on PATH yet - set FFmpegPath in navidrome.toml manually." }

# Python (only needed for configure-lidarr.py; check via `py` launcher first).
$py = $null
$pyc = Get-Command 'py' -ErrorAction SilentlyContinue
if ($pyc) { $py = 'py' }
if (-not $py) {
    Write-Log "Installing Python 3 via winget..."
    winget install --id Python.Python.3.12 -e --accept-source-agreements --accept-package-agreements --silent --disable-interactivity
    $py = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Programs\Python') -Filter 'python.exe' -Recurse -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $py) { Write-Err "Python not available; cannot run Lidarr post-config."; exit 1 }

# ------------------------------------------------------------------ NSSM --
$nssm = Join-Path $nssmHome 'nssm.exe'
if (-not (Test-Path $nssm)) {
    Write-Log "Downloading NSSM..."
    $nssmZip = Join-Path $work 'nssm.zip'
    Invoke-WebRequest -Uri 'https://nssm.cc/release/nssm-2.24.zip' -OutFile $nssmZip
    $nssmExtract = Join-Path $work 'nssm'
    Expand-Archive -Path $nssmZip -DestinationPath $nssmExtract -Force
    New-Item -ItemType Directory -Force -Path $nssmHome | Out-Null
    Copy-Item (Join-Path $nssmExtract 'nssm-2.24\win64\nssm.exe') $nssm -Force
}

# -------------------------------------------------------------- navidrome --
if (-not (Test-Path (Join-Path $ndHome 'navidrome.exe'))) {
    Write-Log "Downloading latest Navidrome..."
    $nd = Get-GithubLatestAsset 'navidrome/navidrome' '*windows_amd64.zip'
    $zip = Join-Path $work $nd.Name
    Invoke-WebRequest -Uri $nd.Url -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $ndHome -Force
}

$ffmpegLine = if ($ffmpeg) { "FFmpegPath = '$($ffmpeg.FullName)'" } else { '' }
$scheduleLine = if ($scanSchedule) { "Scanner.Schedule = '$scanSchedule'" } else { '' }
$navidromeToml = @'
# generated by music-stack - do not edit by hand; re-run the setup script
LogLevel = 'info'
Address = '0.0.0.0'
Port = {PORT}
MusicFolder = '{MUSIC}'
DataFolder = '{DATA}'
{FFMPEG}
{SCHEDULE}
Scanner.WatcherWait = '5s'
'@
$navidromeToml = $navidromeToml.Replace('{PORT}', $ndPort).Replace('{MUSIC}', $musicDir)
$navidromeToml = $navidromeToml.Replace('{DATA}', $ndData).Replace('{FFMPEG}', $ffmpegLine)
$navidromeToml = $navidromeToml.Replace('{SCHEDULE}', $scheduleLine)
Set-Content -LiteralPath (Join-Path $ndData 'navidrome.toml') -Value $navidromeToml -Encoding UTF8
Write-Log "Wrote navidrome.toml (music: $musicDir)"

# ------------------------------------------------------------------ lidarr --
if (-not (Test-Path (Join-Path $lidarrHome 'Lidarr.exe'))) {
    Write-Log "Downloading Lidarr installer..."
    $lidarrInstaller = Join-Path $work 'Lidarr-installer.exe'
    Invoke-WebRequest -Uri 'https://lidarr.servarr.com/v1/update/master/updatefile?os=windows&runtime=netcore&arch=x64&installer=true' `
        -OutFile $lidarrInstaller
    Write-Log "Installing Lidarr silently..."
    Start-Process -Wait -FilePath $lidarrInstaller -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART'
}

# Stop the installer-managed service (if any) so we take over via NSSM.
Remove-ServiceIfPresent 'Lidarr'

$lidarrConfig = @'
<Config>
  <Port>{PORT}</Port>
  <BindAddress>*</BindAddress>
  <ApiKey>{KEY}</ApiKey>
  <UrlBase></UrlBase>
  <UpdateMechanism>External</UpdateMechanism>
  <LaunchBrowser>False</LaunchBrowser>
  <LogLevel>info</LogLevel>
</Config>
'@
$lidarrConfig = $lidarrConfig.Replace('{PORT}', $lidarrPort).Replace('{KEY}', $lidarrKey)
Set-Content -LiteralPath (Join-Path $lidarrData 'config.xml') -Value $lidarrConfig -Encoding UTF8
Write-Log "Wrote Lidarr config.xml (port $lidarrPort)"

# ----------------------------------------------------------------- qbittorrent --
$qbitConf = Join-Path $env:APPDATA 'qBittorrent\qBittorrent.conf'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $qbitConf) | Out-Null
$md5 = [System.Security.Cryptography.MD5]::Create()
$hash = [System.BitConverter]::ToString($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("WebUI API:$qbitPassword")))
$hash = $hash.Replace('-', '').ToLowerInvariant()
$qbitConfBody = @"
[LegalNotice]
Accepted=true
[Preferences]
WebUI\Enabled=true
WebUI\Port=$qbitPort
WebUI\Username=$qbitUser
WebUI\Password=@ByteArray($hash)
WebUI\LocalHostAuth=false
Session\DefaultSavePath=$downloadDir
Session\TempPath=$downloadDir
Session\DiskWriteCacheSize=32
"@
Set-Content -LiteralPath $qbitConf -Value $qbitConfBody -Encoding UTF8
Write-Log "Pre-seeded qBittorrent WebUI config (port $qbitPort)"

# ----------------------------------------------------------------- services --
Remove-ServiceIfPresent 'Navidrome'

Write-Log "Registering Navidrome service..."
& $nssm install Navidrome (Join-Path $ndHome 'navidrome.exe') " --configfile `"$(Join-Path $ndData 'navidrome.toml')`""
& $nssm set Navidrome AppDirectory $ndHome
& $nssm set Navidrome AppStdout (Join-Path $logs 'navidrome.log')
& $nssm set Navidrome AppStderr (Join-Path $logs 'navidrome.log')
& $nssm set Navidrome AppRotateFiles 1
& $nssm set Navidrome AppRotateBytes 10485760
& $nssm set Navidrome Start SERVICE_AUTO_START
& $nssm start Navidrome

Write-Log "Registering Lidarr service..."
& $nssm install Lidarr (Join-Path $lidarrHome 'Lidarr.exe') " -data=`"$lidarrData`""
& $nssm set Lidarr AppDirectory $lidarrHome
& $nssm set Lidarr AppStdout (Join-Path $logs 'lidarr.log')
& $nssm set Lidarr AppStderr (Join-Path $logs 'lidarr.log')
& $nssm set Lidarr AppRotateFiles 1
& $nssm set Lidarr AppRotateBytes 10485760
& $nssm set Lidarr Start SERVICE_AUTO_START
& $nssm start Lidarr

# -------------------------------------------------------- lidarr post-config --
Write-Log "Waiting for Lidarr API, then applying settings..."
$python = if ($py -eq 'py') { 'py' } else { $py }
& $python (Join-Path $repoRoot 'scripts\common\configure-lidarr.py') `
    --settings $Settings --api-key $lidarrKey --port $lidarrPort
if ($LASTEXITCODE -ne 0) { Write-Warn "Lidarr post-config failed (exit $LASTEXITCODE) - run it again after Lidarr is up." }

# ------------------------------------------------------------------ summary --
Write-Host ""
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host " music-stack installed" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host " Navidrome : http://localhost:$ndPort   (create your admin on first visit)"
Write-Host " Lidarr    : http://localhost:$lidarrPort"
Write-Host " qBittorrent WebUI: http://localhost:$qbitPort   (user: $qbitUser)"
Write-Host " Music dir : $musicDir"
Write-Host ""
Write-Host " First steps:" -ForegroundColor Yellow
Write-Host "  1. Open Navidrome and create the admin account."
Write-Host "  2. Open Lidarr -> Settings -> Import Lists, add Last.fm/Spotify to pull in your artists."
Write-Host "  3. Lidarr Settings -> Indexers to add trackers (see config/indexers.json)."
Write-Host "  4. Change the qBittorrent WebUI password in its own UI if prompted."
Write-Host "======================================================================" -ForegroundColor Cyan
