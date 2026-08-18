# Changelog

Version numbers are nominal (no tags have been cut yet); they track the commit history. The
format is [Keep a Changelog](https://keepachangelog.com/)-style: Added / Changed / Fixed, most
recent first.

## Unreleased

### Added

- **`TODO.md`** — near-term, checkbox-level working list behind `ROADMAP.md`, seeded from a gap
  analysis of the stack against Spotify's core value props (recommendations, lyrics, recap).
- **`ROADMAP.md` `v0.6.0` entry** ("Discovery & Spotify parity"): ListenBrainz-powered Discover
  Weekly/Daily Mix playlists, synced-lyrics backfill, and a documented yearly recap — all native,
  no new Docker dependency. Future Vision gained a matching opt-in, Docker-only entry for
  auto-acquiring recommended-but-missing tracks (`re-command`-style), kept explicitly separate
  from the native v0.6.0 work.
- README **"Closing the gap with Spotify"** section summarizing current coverage vs. the gaps
  above, plus a `TODO.md` link in the documentation list.
- **CI validation pipeline** (`.github/workflows/validate.yml`): runs the `MAINTENANCE.md`
  "Testing" checks on every push/PR to `main` — `bash -n` on all four bash scripts, `py_compile`
  on `configure-lidarr.py` (Ubuntu job), and a parse + PSScriptAnalyzer pass (Warning-and-above
  fails) on `Setup-MusicStack.ps1` (Windows job).
- **Badges** (platform, languages, status, release, license) on the README.
- **Mermaid system-overview diagram** inline in the README (replaces the ASCII art).
- **`ROADMAP.md`** — planned work in priority order, mirroring `ARCHITECTURE.md` §7 gaps.
- **`LICENSE`** (MIT), **`CODE_OF_CONDUCT.md`**, **`CONTRIBUTING.md`**, **`SECURITY.md`**, and
  GitHub issue/PR templates (`.github/ISSUE_TEMPLATE/`, `.github/PULL_REQUEST_TEMPLATE.md`).
- README **License** section and links to `CONTRIBUTING.md` / `SECURITY.md`.

## v0.3.0 - Documentation

### Added

- **Documentation**: `ARCHITECTURE.md` (the filesystem contract, platform-parity rule,
  bootstrap chain, and post-config design, with Mermaid diagrams), `TROUBLESHOOTING.md`
  (written from the real incidents below), `MAINTENANCE.md` (parity rule, config generation,
  validation), `CHANGELOG.md`, and `docs/diagrams/` (standalone copies of the architecture
  diagrams). The README now cross-links all of them.

## v0.2.0 - qBittorrent v5 WebUI credentials + finished post-config

### Fixed

- **qBittorrent v5.2 would not start its WebUI** ("WebUI: Credentials are not set"). v5.x reads
  only the PBKDF2-hashed `WebUI\Password_PBKDF2` and ignores the pre-v5 MD5 `WebUI\Password`,
  so the WebUI refused to bind. The scripts now pre-seed **both** password keys (MD5 for ≤5.1,
  PBKDF2 for ≥5.0) and generate the PBKDF2 value from qBittorrent's own spec
  (`base64(salt):base64(PBKDF2-HMAC-SHA512(password, salt, 100000, 64))`) — via
  `Rfc2898DeriveBytes` in PowerShell and a new `ms_qbit_pbkdf2` helper (python3) in bash.
- **qBittorrent v5.2 renamed the Windows config file** from `qBittorrent.conf` to
  `qBittorrent.ini`; pre-seeding only `.conf` was silently ignored. The Windows script now
  writes both files. (Linux/macOS still use `.conf`.)
- **qBittorrent's first-run Legal Notice dialog blocked startup** before the WebUI could bind.
  qBittorrent is now launched with `--confirm-legal-notice`.
- **Lidarr root-folder creation returned HTTP 400** with a minimal `{"path": ...}` body. v3
  requires a full `RootFolderResource` (name, quality + metadata profile ids, monitor options);
  `configure-lidarr.py` now fetches the profile ids and sends the complete body.
- **Lidarr root-folder writability probe failed on workgroup Windows** (machine-account ACEs
  can't be granted by name). The Windows script grants `Everyone:(OI)(CI)(M)` on `MUSIC_DIR`
  and the download dir instead.
- **Post-config raced the services on first boot.** `configure-lidarr.py` now does bounded
  waits for both the Lidarr API and the qBittorrent WebUI port instead of a fixed sleep.
- **Post-config overrides were never passed through** (`MUSIC_DIR`/qBittorrent creds live in the
  scripts' defaults, not the example file). `ms_configure_lidarr` now threads all eight values
  explicitly; all three platform scripts pass them.
- **The post-config used the Lidarr API key generated at script start**, which could go stale;
  the Windows script re-reads the live key from Lidarr's `config.xml` after startup.
- **Lidarr API key could be only 16 characters** on the first release (see v0.1.1); the health
  check for a live machine that kept its short key is covered in `TROUBLESHOOTING.md`.

## v0.1.2 - Default qBittorrent WebUI port changed

### Changed

- Default qBittorrent WebUI port from `8080` to `8443` (`settings.env.example`,
  `configure-lidarr.py` default, all three setup scripts, README).

## v0.1.1 - Fix three Windows setup bugs found in the first real install

### Fixed

- **Navidrome died at startup with a TOML parse error.** `navidrome.toml` was written with a
  UTF-8 BOM by `Set-Content -Encoding UTF8`. The Windows script now writes every config
  BOM-less via `Write-Utf8NoBom`.
- **Lidarr's NSSM service pointed at a nonexistent binary.** The Servarr installer places
  `Lidarr.exe` under `C:\ProgramData\Lidarr\bin\`, not `C:\Program Files\Lidarr\`. The script
  now discovers the binary across both candidate locations and registers the service with
  `-data=<DATA_DIR>\lidarr` plus log rotation.
- **Lidarr API key generation produced only 16 characters** (sampling without replacement from
  a 16-item pool). The generator now emits 32 hex characters — and, importantly, at least 20,
  which Lidarr v3 requires.

## v0.1.0 - Initial release

### Added

- Native (no-Docker) Navidrome + Lidarr + qBittorrent stack for Windows, macOS (Intel), and
  Raspberry Pi, with one shared `MUSIC_DIR` as the only contract between the services.
- Full setup scripts per platform: install ffmpeg/Navidrome/Lidarr/qBittorrent from official
  sources, write configs, register auto-start (NSSM services, LaunchAgents, systemd units),
  grant `MUSIC_DIR` access.
- `settings.env` as single source of truth with random secret generation for empty
  `QBIT_PASSWORD` / `LIDARR_API_KEY`.
- `scripts/common/configure-lidarr.py` post-configuration over the Lidarr REST API: root
  folder, qBittorrent download client, track renaming, optional indexers from
  `config/indexers.json`.
- **True one-liner installs** (`scripts/install.sh`, `scripts/windows/install.ps1`) that
  bootstrap their own package manager (winget / Homebrew) and fetch the repo as a tarball/zip
  — git not required.
- `PSScriptAnalyzerSettings.psd1` lint configuration for the Windows script.
