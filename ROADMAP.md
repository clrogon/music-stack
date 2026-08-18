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

### Priority correction (pre-mortem, 2026-08-18)

A pre-mortem on this project (imagining it failed — see `TODO.md`'s reliability section for the
full list) found that the two most likely causes of failure are both **silent** and both already
tracked in v0.4.0 below: qBittorrent not restarting after a reboot on Windows/macOS (Lidarr keeps
"trying" to grab nothing, forever, with no error), and the absence of a smoke test that would
catch it. Neither is fixed yet. **v0.4.0's reliability items now outrank v0.6.0's Discovery work**
— the roadmap order below already reflects that, but it's worth saying explicitly since I added
v0.6.0 in the same session that surfaced this risk: don't start v0.6.0 until the items marked
**P0** in v0.4.0 are done.

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

* **[P0] Windows qBittorrent auto-start.** qBittorrent is a GUI app on Windows/macOS; macOS has a
  LaunchAgent, Windows has nothing, so a reboot leaves it off until you log in and start it
  manually. Evaluate an at-logon Scheduled Task (or NSSM supervision, if the GUI tolerates it)
  and document whichever is chosen. This is the biggest "not really a service" gap left, and per
  the pre-mortem above it's also the most likely *silent* failure: Lidarr keeps running and
  "trying," Navidrome keeps serving the existing library, and nothing looks broken while
  acquisition has quietly stopped.
* **[P0] Smoke-test script.** A small idempotent checker that asserts all three ports are
  listening, Lidarr's health has no API-key warning, and the qBittorrent WebUI credential
  actually authenticates — the checks `TROUBLESHOOTING.md` documents by hand, scripted. This is
  what would catch item above (and any future silent failure) instead of discovering it weeks
  later.
* **[P0] Backup & disaster-recovery guide.** Nothing in the docs today covers backing up
  `MUSIC_DIR`, `DATA_DIR`, or the Navidrome/Lidarr databases, or recovering onto new hardware. A
  disk failure with no backup story is project-ending, not a bug report. A one-page doc (what to
  back up, how, how to restore) closes most of the risk cheaply.
* **[P0] Reverse-proxy example config.** README already warns the services are "auth-less or
  weakly authed by design" and should only be exposed through "a properly authenticated reverse
  proxy," but ships no example of one. The realistic failure isn't an attacker, it's future-you
  forwarding a router port to qBittorrent's WebUI for convenience because the secure path wasn't
  the easy path. Ship a minimal Caddy or Tailscale Serve example so the safe way is also the
  fastest way.
* **CI validation pipeline.** ✅ Delivered — `.github/workflows/validate.yml` runs the
  `MAINTENANCE.md` checks (bash -n, PSScriptAnalyzer, `py_compile`) on push/PR to `main` so a
  broken `lib.sh` or a new PSScriptAnalyzer finding can't merge. **Gap still open:** this only
  lints/syntax-checks — it never installs and runs the real Navidrome/Lidarr/qBittorrent
  binaries, so it would not have caught any of the four real upstream-version breakages already
  recorded in `TROUBLESHOOTING.md` (BOM parsing, Lidarr's binary path, the API-key length
  requirement, qBittorrent v5.2's config rename + PBKDF2 requirement). A periodic
  install-against-latest-upstream CI job is the only thing that catches the next one before a
  live install does.
* **Real macOS and Raspberry Pi install pass.** Every recorded real-install incident in
  `TROUBLESHOOTING.md`/`CHANGELOG.md` happened on Windows; there's no equivalent evidence the
  macOS or Pi scripts have been run against real hardware. The "parity rule" (`MAINTENANCE.md`)
  is enforced by discipline alone with no reviewer — worth an actual live run on both to find
  what Windows-only testing has missed, rather than trusting the mirrored-code discipline to
  have held.
* **Pinned-URL link check.** Mirror dev-sandbox's weekly workflow that HEAD-checks every pinned
  fallback download URL, so a dead Navidrome/Lidarr/winget URL is caught within a week instead
  of at the next install.
* **Apple Silicon support.** macOS is currently Intel-only (`darwin_amd64`). Detect `arm64`,
  download the `darwin_arm64` Navidrome/Lidarr builds, and keep the parity rule intact.
* **Indexer setup guide (honesty check).** `TROUBLESHOOTING.md` already documents "no indexers"
  as expected, not a bug, but the README's "complete my library" promise quietly depends on the
  user clearing private-tracker/usenet friction that the codebase can't automate. Either write a
  short guide that actually gets someone from zero to one working indexer, or soften the
  README's claim to match what's realistic without one.

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

## v0.6.0 - Discovery & Spotify parity

**Blocked on v0.4.0's `[P0]` items above.** Per the pre-mortem correction: shipping recommendation
playlists while acquisition can silently die unnoticed is solving the wrong problem first.

Closes the biggest experiential gap versus Spotify: personalized recommendations, lyrics, and a
listening recap. Comes from a gap analysis of the shipped stack against Spotify's core value
props — the working checklist is `TODO.md`. Stays inside the native-install, no-Docker-by-default
line from Orientation above: everything here is either Navidrome-native or a small stdlib script
mirroring the existing `configure-lidarr.py` REST post-config pattern, not a new dependency
surface.

* **ListenBrainz-powered Discover Weekly / Daily Mix.** Navidrome already scrobbles natively to
  ListenBrainz; add a `LISTENBRAINZ_TOKEN` setting and install the community
  `navidrome-listenbrainz-daily-playlist` plugin so daily/weekly/exploration playlists generate
  automatically — the closest native equivalent to Spotify's Discover Weekly and Daily Mix.
* **Synced lyrics.** Navidrome displays `.lrc`/embedded lyrics but never fetches them. Add
  `scripts/common/fetch-lyrics.py` (stdlib + the free, unauthenticated lrclib.net API) to backfill
  missing `.lrc` files across `MUSIC_DIR`, idempotently.
* **Yearly recap.** No install needed — ListenBrainz's own Year-in-Review page works automatically
  once scrobbling is wired up above. Document it in the README rather than building anything.
* Update `ARCHITECTURE.md` §5 and `MAINTENANCE.md` once the plugin wiring and lyrics script land,
  since both add new components that speak to a service's API.

---

## Future vision

What's left after the gaps are closed — requires user secrets or a real feature decision, so it
stays out of the versioned work:

* **Import-list automation.** Lidarr's Last.fm/Spotify import lists make "follow artists, get
  their missing albums" automatic, but need API keys. Automate their registration via the same
  REST-post-config pattern once a user supplies credentials.
* **Auto-acquire recommended-but-missing tracks (opt-in, Docker).** Tools like `re-command`
  chain ListenBrainz/Last.fm/LLM recommendations to an actual downloader (Soulseek/Deezer) and
  drop results straight into `MUSIC_DIR` — the closest thing to "Spotify recommends it, and now
  I own it," distinct from v0.6.0's native recommendation *playlists*. Docker-only with an
  LLM/Deezer/Soulseek credential surface, so it ships as an explicitly opt-in appendix, never
  the default install path, per the Docker non-goal below.
* **Monitoring.** A per-service health page or `systemctl`/NSSM status digest; only meaningful
  once v0.4.0's smoke-test checker exists to build on.
* **Podcasts.** Navidrome supports podcasts; folding them in changes the product's scope (a
  "music" stack becomes a "media" stack). Revisit deliberately, not by accident.
* **Docker compose as an explicit non-goal.** Documented here so the decision is visible: the
  native-only line in Orientation means this is not coming as the default path.

Not yet scoped into versioned tasks — revisit once v0.4.0 is underway and the CI/smoke-test
baseline exists.
