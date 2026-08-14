# Contributing

Thank you for contributing to music-stack.

## Contribution Guidelines

### Reporting Issues

When opening an issue, include:

* Platform (Windows / macOS Intel / Raspberry Pi)
* OS version (e.g. Windows 11 24H2, macOS 14 Sonoma, Raspberry Pi OS Bookworm)
* Script name (`windows/setup.ps1`, `macos/setup.sh`, `raspberry-pi/setup.sh`,
  `scripts/common/lib.sh`, `scripts/common/configure-lidarr.py`)
* `settings.env` contents **with the password redacted**
* Repository version (`git describe --tags` or the tag/branch used)
* Error message
* Relevant logs (see `TROUBLESHOOTING.md` for where each service writes them)

### Pull Requests

Before submitting:

* Verify scripts execute successfully on at least one real platform.
* Mirror any change to a platform script in the **other two** — the three scripts must stay
  behaviorally identical (the parity rule, `ARCHITECTURE.md` §2). A fix to Windows almost
  always belongs on macOS and Raspberry Pi too.
* Preserve existing logging and convention style.
* Maintain idempotent behavior: re-running any script must be safe.
* Never write config files with a BOM — use BOM-less UTF-8 (see `MAINTENANCE.md`; a UTF-8 BOM
  breaks Navidrome's TOML parser).
* Avoid hard-coded paths and machine-specific values; defaults belong in the script, overrides
  in `settings.env`.
* Avoid embedding credentials or secrets — including not printing them at trace level.

### Validation

Run all three before pushing (documented in `MAINTENANCE.md`):

```bash
bash -n install.sh macos/setup.sh raspberry-pi/setup.sh scripts/common/lib.sh
```

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

```bash
python3 -m py_compile scripts/common/configure-lidarr.py
```

There is no CI yet (tracked in `ROADMAP.md` v0.4.0), so these run by hand — treat them as
mandatory, not optional.

### Security Requirements

Pull requests must not include:

* Credentials
* Tokens
* Certificates
* Internal infrastructure references
* Proprietary software binaries

### Testing

All changes should be tested against at least one of:

* Windows 10/11 with PowerShell 5.1
* macOS (Intel) with bash
* Raspberry Pi 3/4/5 with bash

State which platform you tested on in the PR description.

Thank you for helping improve the project.
