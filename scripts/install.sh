#!/usr/bin/env bash
# music-stack one-liner bootstrap for macOS (Intel/ARM) and Raspberry Pi.
#
#   macOS:  curl -fsSL https://raw.githubusercontent.com/clrogon/music-stack/main/scripts/install.sh | bash
#   Pi:     curl -fsSL https://raw.githubusercontent.com/clrogon/music-stack/main/scripts/install.sh | sudo bash
#
# Fetches the repo (tarball, so git is not required), then runs the platform
# setup script. That script bootstraps the missing package manager (Homebrew
# on macOS) and generates settings.env with a random qBittorrent password if
# you have not created one.
#
# Requires only: bash, and either curl or wget (both ship with macOS and
# Raspberry Pi OS). Set MS_BRANCH to install from a different branch.
set -euo pipefail

BRANCH="${MS_BRANCH:-main}"
REPO="clrogon/music-stack"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fetch() {
  local url="$1" dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 --connect-timeout 20 -o "$dest" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$dest" "$url"
  else
    echo "[x] this one-liner needs curl or wget, but neither is installed" >&2
    exit 1
  fi
}

echo "[+] music-stack one-liner (branch: $BRANCH)"
fetch "https://codeload.github.com/$REPO/tar.gz/refs/heads/$BRANCH" "$TMP/music-stack.tar.gz"
tar -xzf "$TMP/music-stack.tar.gz" -C "$TMP"
cd "$TMP/music-stack-$BRANCH"

case "$(uname -s)" in
  Darwin) exec bash scripts/macos/setup.sh ;;
  Linux)  exec bash scripts/raspberry-pi/setup.sh ;;
  *)      echo "[x] unsupported platform: $(uname -s)" >&2; exit 1 ;;
esac
