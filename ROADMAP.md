# Roadmap

## Orientation

This is a personal, self-hosted stack, but it is structured as a community tool: three
platform scripts that must stay behaviorally identical, one shared contract, and nothing
assuming a specific machine. That shapes two standing priorities across every version below:

* **Native installs are the design line, not a constraint to work around.** The stack
  deliberately has no Docker or shared runtime; every service runs as a native app supervised
  by the platform's own mechanism. Anything that would require Docker as the *default* path is
  out of scope. (If a future version adds an alternative, it must be additive and opt-in.)
* **The manual-by-design items stay manual.** Indexer credentials and Navidrome's first admin
  account cannot be automated without the user's secrets, and shipping defaults for them would
  be a security hole. The roadmap closes *automatable* gaps only — see `ARCHITECTURE.md` §7 for
  the standing list.

No hard deadline drives this roadmap — it's self-paced, worked in the priority order below.
Gaps tracked here mirror `ARCHITECTURE.md` §7 and `MAINTENANCE.md`.

---

## v0.3.0 - Delivered

The first release cut. Summary — see `CHANGELOG.md` for the full writeup:

* Native Navidrome + Lidarr + qBittorrent stack on Windows, macOS (Intel), Raspberry Pi, with
  `MUSIC_DIR` as the only contract (the design in `ARCHITECTURE.md`).
* One-liner installs that bootstrap their own package manager; `settings.env` as the single
  source of truth with generated secrets.
* REST post-configuration (`configure-lidarr.py`): root folder, qBittorrent client, naming,
  optional indexers.
* Real-install fixes: BOM-less configs (Navidrome TOML), Lidarr's `ProgramData\bin` discovery,
  ≥20-char API keys, qBittorrent v5's `.ini` rename + PBKDF2 `Password_PBKDF2` credentials,
  full-v3 root-folder body, `Everyone` grants for workgroup Windows.
* Full documentation: `ARCHITECTURE.md`, `TROUBLESHOOTING.md`, `MAINTENANCE.md`,
  `CHANGELOG.md`, `ROADMAP.md`, and standalone Mermaid diagrams in `docs/diagrams/`.

---

## v0.4.0 - Close the known gaps

Not new capability — closes the gaps `ARCHITECTURE.md` §7 already documents as open. Small,
low-risk, and touches the current scripts rather than the architecture. See `MAINTENANCE.md`
for the per-script touchpoints.

* **Windows qBittorrent auto-start.** qBittorrent is a GUI app on Windows/macOS; macOS has a
  LaunchAgent, Windows has nothing, so a reboot leaves it off until you log in and start it
  manually. Evaluate an at-logon Scheduled Task (or NSSM supervision, if the GUI tolerates it)
  and document whichever is chosen. This is the biggest "not really a service" gap left.
* **CI validation pipeline.** ✅ Delivered — `.github/workflows/validate.yml` runs the
  `MAINTENANCE.md` checks (bash -n, PSScriptAnalyzer, `py_compile`) on push/PR to `main` so a
  broken `lib.sh` or a new PSScriptAnalyzer finding can't merge.
* **Pinned-URL link check.** Mirror dev-sandbox's weekly workflow that HEAD-checks every pinned
  fallback download URL, so a dead Navidrome/Lidarr/winget URL is caught within a week instead
  of at the next install.
* **Apple Silicon support.** macOS is currently Intel-only (`darwin_amd64`). Detect `arm64`,
  download the `darwin_arm64` Navidrome/Lidarr builds, and keep the parity rule intact.
* **Smoke-test script.** A small idempotent checker that asserts all three ports are listening,
  Lidarr's health has no API-key warning, and the qBittorrent WebUI credential actually
  authenticates — the checks `TROUBLESHOOTING.md` documents by hand, scripted.

---

## v0.5.0 - Automation and distribution

Depends on v0.4.0's CI to be safe to run unattended.

* **Release automation.** Cut versions, tags, and GitHub releases from CI (bump version in
  `CHANGELOG.md`, tag, `gh release create` with generated notes) instead of by hand.
* **Homebrew tap** (`clrogon/homebrew-music-stack`) so macOS users can
  `brew install` the stack alongside the existing one-liner; the tap repo is the only "package"
  form that fits a script-based installer. Decide and document whether it's worth the
  maintenance, rather than defaulting to yes.
* **Indexer presets.** Ship curated `config/indexers.json` presets for the common music trackers
  (username/password fields left blank), so enabling a tracker is fill-in-the-blanks rather than
  Cardigann schema spelunking.

---

## Future vision

What's left after the gaps are closed — requires user secrets or a real feature decision, so it
stays out of the versioned work:

* **Import-list automation.** Lidarr's Last.fm/Spotify import lists make "follow artists, get
  their missing albums" automatic, but need API keys. Automate their registration via the same
  REST-post-config pattern once a user supplies credentials.
* **Monitoring.** A per-service health page or `systemctl`/NSSM status digest; only meaningful
  once v0.4.0's smoke-test checker exists to build on.
* **Podcasts.** Navidrome supports podcasts; folding them in changes the product's scope (a
  "music" stack becomes a "media" stack). Revisit deliberately, not by accident.
* **Docker compose as an explicit non-goal.** Documented here so the decision is visible: the
  native-only line in Orientation means this is not coming as the default path.

Not yet scoped into versioned tasks — revisit once v0.4.0 is underway and the CI/smoke-test
baseline exists.
