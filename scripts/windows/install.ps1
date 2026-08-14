# music-stack one-liner bootstrap for Windows (PowerShell 5.1+).
#
#   powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/clrogon/music-stack/main/scripts/windows/install.ps1 | iex"
#
# Bootstraps its own prerequisites instead of assuming them:
#   1. winget / App Installer - installed from the official microsoft/winget-cli
#      GitHub release (msixbundle + dependencies) when missing. No Store needed.
#   2. The repo - fetched as a zip, so git is not required.
#   3. Delegates to Setup-MusicStack.ps1, which auto-elevates, auto-creates
#      settings.env with a generated qBittorrent password, installs ffmpeg /
#      qBittorrent / Python via winget, and registers auto-start services.
#
# Run from a normal (non-admin) shell; elevation is handled for you. Set the
# MS_BRANCH environment variable to install from a different branch.
#
# NOTE: this script is invoked via `irm | iex`, which runs it inside your shell,
# so it deliberately never calls `exit` (that would close your terminal). On
# failure it warns and `return`s; the delegated setup runs in its own process.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$branch = if ($env:MS_BRANCH) { $env:MS_BRANCH } else { 'main' }
$repo   = 'clrogon/music-stack'
$work   = Join-Path $env:TEMP 'music-stack-bootstrap'
New-Item -ItemType Directory -Force -Path $work | Out-Null

Write-Host "[+] music-stack one-liner (branch: $branch)"

# ------------------------------------------------------------- 1. winget --
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host "[+] winget not found - installing App Installer from the winget-cli GitHub release..." -ForegroundColor Green
    try {
        $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases/latest' -Headers @{'User-Agent' = 'music-stack'}
        $bundle = $rel.assets | Where-Object { $_.name -like 'Microsoft.DesktopAppInstaller_*.msixbundle' } | Select-Object -First 1
        $deps   = $rel.assets | Where-Object { $_.name -eq 'DesktopAppInstaller_Dependencies.zip' } | Select-Object -First 1
        if (-not $bundle -or -not $deps) { throw 'winget release assets not found' }

        $bundleFile = Join-Path $work $bundle.name
        $depsFile   = Join-Path $work 'winget-deps.zip'
        $depsDir    = Join-Path $work 'winget-deps'
        Invoke-WebRequest -Uri $bundle.browser_download_url -OutFile $bundleFile
        Invoke-WebRequest -Uri $deps.browser_download_url -OutFile $depsFile
        Expand-Archive -Path $depsFile -DestinationPath $depsDir -Force
        Get-ChildItem -Path $depsDir -Include '*.appx', '*.msix' -Recurse | ForEach-Object {
            try { Add-AppxPackage -Path $_.FullName -ErrorAction Stop }
            catch { Write-Warning "dependency install failed (continuing): $($_.Exception.Message)" }
        }
        Add-AppxPackage -Path $bundleFile -ErrorAction Stop

        $env:PATH = "$env:PATH;$env:LOCALAPPDATA\Microsoft\WindowsApps"
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw 'winget still unavailable after install' }
    }
    catch {
        Write-Warning "Could not install winget automatically: $($_.Exception.Message)"
        Write-Warning "Install 'App Installer' from the Microsoft Store, close and reopen PowerShell, then re-run this one-liner."
        return
    }
}

# ------------------------------------------------------------ 2. fetch repo --
$zipFile = Join-Path $work 'music-stack.zip'
Invoke-WebRequest -Uri "https://codeload.github.com/$repo/zip/refs/heads/$branch" -OutFile $zipFile
$repoDir = Join-Path $work "music-stack-$branch"
if (Test-Path -LiteralPath $repoDir) { Remove-Item -LiteralPath $repoDir -Recurse -Force }
Expand-Archive -Path $zipFile -DestinationPath $work -Force

# ---------------------------------------------------------- 3. delegate ---------
Write-Host "[+] running Setup-MusicStack.ps1 (auto-elevates)..." -ForegroundColor Green
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoDir 'scripts\windows\Setup-MusicStack.ps1') -Settings (Join-Path $repoDir 'settings.env')
