# Maintenance guide

This document describes how to modify and test the setup scripts. It is written for the
maintainer of this repo — if you are setting up a machine, see `README.md`; if something is
broken, see `TROUBLESHOOTING.md`.

## File structure

```
music-stack/
  README.md                    # User-facing documentation
  ARCHITECTURE.md              # Why the stack is structured this way (with diagrams)
  TROUBLESHOOTING.md           # Common issues, written from real incidents
  MAINTENANCE.md               # This file
  CHANGELOG.md                 # Version history
  settings.env.example         # Template copied to settings.env (never ship real secrets)
  PSScriptAnalyzerSettings.psd1 # Lint config for the Windows script
  config/
    indexers.example.json      # Optional Lidarr indexer registrations
  docs/diagrams/
    *.mmd                      # Standalone copies of the ARCHITECTURE.md diagrams
  scripts/
    install.sh                 # One-liner bootstrap (macOS + Raspberry Pi)
    common/
      lib.sh                   # POSIX helpers shared by macOS + Pi
      configure-lidarr.py      # Post-config over the Lidarr REST API (all platforms)
    windows/
      install.ps1              # One-liner bootstrap (installs winget if absent)
      Setup-MusicStack.ps1     # The Windows setup script
    macos/setup.sh
    raspberry-pi/setup.sh
```

## The parity rule (most important rule in this repo)

The Windows, macOS, and Raspberry Pi scripts must stay **behaviorally identical**: same ports,
same `settings.env` semantics, same generated configs, same idempotency, same post-config.
A change to one script almost always needs the mirrored change in the other two. The shared
logic lives in `scripts/common/` precisely to keep the platform scripts thin.

The deliberate exceptions — places where behavior legitimately differs — are listed in
`ARCHITECTURE.md` §2 (package managers, service supervisors, qBittorrent *form*). If you catch
yourself adding a platform-specific branch to behavior that is *not* in that table, you are
breaking the rule.

### The three places that must move in lockstep

| Concern | Where in each script |
| --- | --- |
| Defaults for empty `settings.env` values | `ms_setting`/`ms_setting_path` fallbacks in `lib.sh`; the `$script:Default*` block in `Setup-MusicStack.ps1` |
| Config file generation | The navidrome/Lidarr/qBittorrent config write blocks |
| The post-config call | `ms_configure_lidarr` in `lib.sh` (macOS + Pi call it) and the inline python invocation in `Setup-MusicStack.ps1` |

## How configuration flows

### `settings.env` is the single source of truth

Every script reads `settings.env` (next to the setup script, or in the bootstrap temp dir for
one-liners) through the same helpers and falls back to per-platform defaults for empty values.
The *scripts* own the defaults — `settings.env.example` documents them but is not a defaults
file. This is why the post-config call passes every value explicitly rather than letting
`configure-lidarr.py` guess: the Python script has no knowledge of per-platform defaults.

### Config writes must be BOM-less

Windows PowerShell's `Set-Content -Encoding UTF8` writes a UTF-8 BOM, which is fatal to
Navidrome's TOML parser. The Windows script routes all config writes through
`Write-Utf8NoBom` (`[System.IO.File]::WriteAllText` with a `UTF8Encoding($false)`). **Never
reintroduce `Set-Content -Encoding UTF8` for a config file** — `settings.env` reads are fine
either way, but `navidrome.toml`, Lidarr's `config.xml`, and qBittorrent's config must stay
BOM-less. The bash scripts write via heredocs, which never emit a BOM.

### Secrets: generated, never shipped

- `LIDARR_API_KEY` — if empty, generated as **32 hex characters**. Lidarr v3 rejects keys
  shorter than 20 characters, so a 16-char generator is a bug (it was one once). Correct form:
  `-join (1..32 | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })`.
- `QBIT_PASSWORD` — if empty, generated randomly and printed once.

Never commit a `settings.env` with real values; the file is gitignored.

### qBittorrent credential format (the trap that keeps giving)

qBittorrent's WebUI password storage changed twice and bit us both times:

1. **v5.2 renamed the Windows config file** `qBittorrent.conf` → `qBittorrent.ini`
   (`%APPDATA%\qBittorrent\`). On Windows the script must seed **both** files. Linux/macOS
   still use `.conf`.
2. **v5.x reads only `WebUI\Password_PBKDF2`**; the pre-v5 MD5 `WebUI\Password` is ignored, and
   an empty PBKDF2 value makes the WebUI refuse to start ("Credentials are not set"). The
   scripts write **both** keys (MD5 for ≤5.1, PBKDF2 for ≥5.0).

The PBKDF2 value format (from qBittorrent `src/base/utils/password.cpp`): 100000 iterations of
HMAC-SHA512, 64-byte output, 16-byte random salt, stored as
`base64(salt) + ":" + base64(key)` inside `@ByteArray(...)`:

```
WebUI\Password_PBKDF2=@ByteArray(<saltBase64>:<keyBase64>)
```

It is reproduced in PowerShell via
`Rfc2898DeriveBytes(password, salt, 100000, HashAlgorithmName.SHA512).GetBytes(64)` and in bash
via `ms_qbit_pbkdf2` (python3 `hashlib.pbkdf2_hmac`). If qBittorrent ever changes this again,
update `Setup-MusicStack.ps1` and `ms_qbit_pbkdf2` in `lib.sh` together.

qBittorrent is also launched with `--confirm-legal-notice` so the first-run Legal Notice dialog
cannot block startup before the WebUI binds.

### Lidarr binary location on Windows

The Servarr Windows installer puts binaries in `C:\ProgramData\Lidarr\bin\`, not
`C:\Program Files\Lidarr\`. The Windows script discovers the binary across both candidate
locations (`bin\Lidarr.exe`, then the legacy Program Files path), errors if neither exists, and
registers the NSSM service with `-data=<DATA_DIR>\lidarr` so the database lands in `DATA_DIR`.

## The post-config call

`scripts/common/configure-lidarr.py` is the only component that talks to a service API. It is
python3-stdlib only, idempotent, and does bounded waits (Lidarr API up, qBittorrent WebUI port
bound) rather than fixed sleeps.

Arguments (all overridable on the command line):

| Flag | Source | Notes |
| --- | --- | --- |
| `--settings` | **required** | path to `settings.env` |
| `--api-key` | `LIDARR_API_KEY` | dies if neither given |
| `--port` | `LIDARR_PORT` | default `8686` |
| `--host` | — | default `127.0.0.1` |
| `--timeout` | — | default `300` s total |
| `--music-dir` | `MUSIC_DIR` | dies if empty (scripts must pass it — the script does) |
| `--qbit-user` / `--qbit-password` | `QBIT_USER` / `QBIT_PASSWORD` | dies if password empty |
| `--qbit-port` | `QBIT_PORT` | default `8443` |

The bash side wraps it as `ms_configure_lidarr <api_key> <port> <settings> <python> <music_dir>
<qbit_user> <qbit_password> <qbit_port>` — **8 positional args, passed explicitly** because the
scripts (not the example file) own the defaults. `Setup-MusicStack.ps1` invokes the same python
with the same flags. If you change the flag set, update all three call sites and this table.

### Root folder body is v3-shaped

Lidarr v3 rejects a bare `{"path": ...}` with HTTP 400. `ensure_root_folder` POSTs a full
`RootFolderResource`: `name` (leaf), `defaultMetadataProfileId` / `defaultQualityProfileId`
(fetched from `/qualityprofile` and `/metadataprofile`), `defaultMonitorOption` /
`defaultNewItemMonitorOption` = `all`, `defaultTags` = `[]`. Keep it that way.

## Making changes

### Change a default port

1. Update `settings.env.example`.
2. Update the default in `lib.sh` (`ms_setting` fallback), in `Setup-MusicStack.ps1`, and in
   `setup.sh` for macOS and Pi if they hardcode it anywhere.
3. Update this repo's README port table and `ARCHITECTURE.md` §2 if the value is named there.
4. Note it in `CHANGELOG.md` — port changes are exactly the kind of thing users who pinned a
   port will hit.

### Add a download client

The post-config currently registers qBittorrent specifically. To support another client, add
its registration next to the qBittorrent one in `configure-lidarr.py` and thread its
credentials through `settings.env` + `settings.env.example` + all three setup scripts. Keep the
same idempotent read-modify-write pattern.

### Add a fourth platform

Add a `scripts/<platform>/setup.sh` that: reads settings through the same semantics, installs
the three services natively, registers auto-start, grants `MUSIC_DIR` access, then calls
`ms_configure_lidarr` from `lib.sh` after Lidarr is up. Add the one-liner wiring in
`scripts/install.sh` and a row in the README's install table. Then reconcile every §"three
places in lockstep" row.

## Testing

There is no CI on this repo yet, so validation is manual and scripted:

```powershell
# 1. bash syntax — every bash file (lib.sh, both setup.sh, install.sh):
bash -n scripts/install.sh scripts/macos/setup.sh scripts/raspberry-pi/setup.sh scripts/common/lib.sh

# 2. Windows script — parse + PSScriptAnalyzer (warning+ = failure):
$e = $null; $t = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    'scripts/windows/Setup-MusicStack.ps1', [ref]$t, [ref]$e) | Out-Null
if ($e.Count) { $e | ForEach-Object Message }
Invoke-ScriptAnalyzer -Path scripts/windows/Setup-MusicStack.ps1 `
    -Settings PSScriptAnalyzerSettings.psd1

# 3. Post-config — python compiles:
py -m py_compile scripts/common/configure-lidarr.py
```

(The `Write-Host` / `PSUseShouldProcessForStateChangingFunctions` warnings from step 2 are
pre-existing and accepted by convention — see the notes in `PSScriptAnalyzerSettings.psd1`.)

### Functional checks against a live machine

With a running stack (`http://localhost:8686`, `:4533`, `:8443`):

```powershell
# All three ports listening:
Get-NetTCPConnection -State Listen -LocalPort 4533,8686,8443

# Lidarr healthy (no API-key warning) and post-config applied:
Invoke-RestMethod http://127.0.0.1:8686/api/v1/health -Headers @{ 'X-Api-Key' = $key }
Invoke-RestMethod http://127.0.0.1:8686/api/v1/rootfolder -Headers @{ 'X-Api-Key' = $key }
Invoke-RestMethod http://127.0.0.1:8686/api/v1/downloadclient -Headers @{ 'X-Api-Key' = $key }

# qBittorrent credentials actually authenticate (not just the port bound):
(Invoke-WebRequest -Uri 'http://127.0.0.1:8443/api/v2/auth/login' -Method Post `
    -Body @{ username = 'admin'; password = $qbitPassword } -UseBasicParsing).Content
```

And the idempotency check: re-run the post-config twice; the second run must report everything
"already configured" and exit 0.

### Idempotency + dry-run conventions

- Setup scripts are **idempotent**: installs are skipped when the tool is present, configs are
  regenerated only when the target file is absent or missing a required key, services are
  re-registered without error.
- The post-config is read-modify-write: root folder, download client, and naming are only
  created/toggled when missing/off.
- There is **no dry-run flag** in this repo today (unlike the Image-Factory convention); the
  one-liner is the safety net. If you add a mutating step, keep it idempotent.

## Before committing

1. `bash -n` on all four bash files.
2. PSScriptAnalyzer on the Windows script — no *new* findings.
3. `py -m py_compile` on `configure-lidarr.py`.
4. Re-ran the live post-config and confirmed the idempotent second run.
5. `CHANGELOG.md` updated under `Unreleased`.
6. Grep the diff for secrets (`settings.env`, API keys, passwords) — never commit real values.
