#!/usr/bin/env bash
# lib.sh — shared helpers for the macOS and Raspberry Pi setup scripts.
# Shellcheck-clean for bash.

set -euo pipefail

# ---------------------------------------------------------------- logging --
ms_log()  { printf '\033[32m[+]\033[0m %s\n' "$*"; }
ms_warn() { printf '\033[33m[!]\033[0m %s\n' "$*"; }
ms_err()  { printf '\033[31m[x]\033[0m %s\n' "$*"; }
ms_die()  { ms_err "$*"; exit 1; }

ms_require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || ms_die "required command not found: $cmd"
}

# ----------------------------------------------------------------- settings --
# Locate settings.env: $MS_SETTINGS, else ./settings.env, else repo-root.
MS_SETTINGS="${MS_SETTINGS:-}"
if [[ -z "$MS_SETTINGS" ]]; then
  if [[ -f "./settings.env" ]]; then
    MS_SETTINGS="./settings.env"
  elif [[ -f "$(dirname "${BASH_SOURCE[0]}")/../settings.env" ]]; then
    MS_SETTINGS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/settings.env"
  fi
fi

# ms_setting <key> [default] — value of KEY in settings.env, or default.
ms_setting() {
  local key="$1" default="${2:-}" val="" line
  if [[ -n "$MS_SETTINGS" && -f "$MS_SETTINGS" ]]; then
    while IFS= read -r line; do
      case "$line" in
        \#*|'') continue ;;
      esac
      if [[ "$line" == "$key="* ]]; then
        val="${line#*=}"
        break
      fi
    done < "$MS_SETTINGS"
  fi
  if [[ -z "$val" ]]; then
    printf '%s' "$default"
  else
    printf '%s' "$val"
  fi
}

# ms_setting_path <key> [default] — like ms_setting but expands ~.
ms_setting_path() {
  local key="$1" default="${2:-}"
  local val
  val="$(ms_setting "$key" "$default")"
  printf '%s' "${val/#\~/$HOME}"
}

# -------------------------------------------------------------------- misc --
ms_random_hex() {
  local n="${1:-16}"
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex "$n"
  else
    head -c "$n" /dev/urandom | od -An -tx1 | tr -d ' \n'
  fi
}

# ms_download <url> <dest> — downloads with curl, fails on error/HTTP>=400.
ms_download() {
  local url="$1" dest="$2" dir
  dir="$(dirname "$dest")"
  mkdir -p "$dir"
  curl -fsSL --retry 3 --connect-timeout 20 -o "$dest" "$url" \
    || ms_die "download failed: $url"
}

# ms_wait_http <url> <timeout_sec> — poll until the URL answers or timeout.
ms_wait_http() {
  local url="$1" timeout="${2:-180}" tries=$(( "${2:-180}" / 5 ))
  local i=0
  while (( i < tries )); do
    if curl -fsS -o /dev/null --max-time 3 "$url" 2>/dev/null; then
      return 0
    fi
    i=$(( i + 1 ))
    sleep 5
  done
  ms_die "service did not answer at $url within ${timeout}s"
}

# --------------------------------------------------------------- navidrome --
# ms_latest_navidrome <os> <arch> — echoes "tag asset_url".
# os:   darwin | linux | windows
# arch: amd64 | arm64 | armv7 | armv6 | 386
ms_latest_navidrome() {
  local os="$1" arch="$2" tag
  tag="$(curl -fsSL https://api.github.com/repos/navidrome/navidrome/releases/latest \
         | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)"
  [[ -n "$tag" ]] || ms_die "could not resolve latest Navidrome release"
  printf '%s https://github.com/navidrome/navidrome/releases/download/%s/navidrome_%s_%s_%s.tar.gz\n' \
    "$tag" "$tag" "$tag" "$os" "$arch"
}

# ms_navidrome_arch <uname-m> — maps machine arch to a Navidrome build suffix.
ms_navidrome_arch() {
  local m="$1"
  case "$m" in
    x86_64|amd64)  printf 'amd64' ;;
    aarch64|arm64) printf 'arm64' ;;
    armv7l|armv6l) printf 'armv7' ;;
    *) ms_die "unsupported architecture for Navidrome: $m" ;;
  esac
}

# ------------------------------------------------------------------ lidarr --
# ms_latest_lidarr <os> <arch> — echoes the download URL.
# os:   osx | linux | windows     arch: x64 | arm | arm64
ms_latest_lidarr() {
  local os="$1" arch="$2"
  printf 'https://lidarr.servarr.com/v1/update/master/updatefile?os=%s&runtime=netcore&arch=%s' \
    "$os" "$arch"
}

# ----------------------------------------------------------- post configure --
# ms_configure_lidarr <api_key> <port> <settings_file> <python>
ms_configure_lidarr() {
  local api_key="$1" port="$2" settings="$3" python="$4"
  local py="scripts/common/configure-lidarr.py"
  if [[ ! -f "$py" ]]; then
    # Fall back to repo-relative path when invoked from elsewhere.
    local repo
    repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    py="$repo/scripts/common/configure-lidarr.py"
  fi
  ms_log "Configuring Lidarr (root folder, download client, naming, indexers)..."
  "$python" "$py" --settings "$settings" --api-key "$api_key" --port "$port"
}
