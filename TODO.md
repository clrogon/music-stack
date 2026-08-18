# TODO

Near-term, actionable checklist. This is the working list; `ROADMAP.md` is the versioned,
narrative form of the same priorities, and `CHANGELOG.md` records what actually shipped. Check
items off here as they land, then fold the summary into `CHANGELOG.md` under `Unreleased` the
way every prior change has been.

## P0 — Reliability corrections (pre-mortem, 2026-08-18)

A pre-mortem on this project ("imagine it failed 12 months from now — why?") found the two most
likely causes are both **silent failures** in the v0.4.0 work, not missing features. These
tickets outrank everything below, including the Discovery batch — see `ROADMAP.md`'s priority
correction note for the reasoning.

- [ ] **Windows qBittorrent auto-start.** No supervision today (GUI app, launched not serviced);
      a reboot leaves it off with no error anywhere. Evaluate an at-logon Scheduled Task or NSSM
      supervision, document whichever is chosen. **Highest priority item in this file** — this is
      the actual failure mode most likely to kill the project (Lidarr "runs" and grabs nothing,
      Navidrome keeps serving the existing library, nothing looks broken).
- [ ] **Smoke-test script.** Idempotent checker: all three ports listening, Lidarr health has no
      API-key warning, qBittorrent WebUI credential actually authenticates. This is what catches
      the item above automatically instead of discovering it weeks later.
- [ ] **Backup & disaster-recovery guide.** One page: what to back up (`MUSIC_DIR`, `DATA_DIR`,
      Navidrome/Lidarr databases), how, and how to restore onto new hardware. Nothing covers this
      today; a dead disk with no backup plan is project-ending, not a bug report.
- [ ] **Reverse-proxy example config.** README warns the services are "auth-less or weakly
      authed by design" but ships no example of the recommended fix. Add a minimal Caddy or
      Tailscale Serve config so the secure path is also the easy path — the realistic risk is
      future-you port-forwarding qBittorrent's WebUI directly for convenience.
- [ ] **Live-install / integration CI.** Current CI only lints and syntax-checks; it would not
      have caught any of the four real upstream-version breakages already in
      `TROUBLESHOOTING.md` (Navidrome BOM parsing, Lidarr's binary path move, the API-key length
      requirement, qBittorrent v5.2's config rename + PBKDF2 requirement). Add a periodic job
      that installs and runs the real binaries against latest upstream.
- [ ] **Real macOS and Raspberry Pi install pass.** Every recorded real-install incident on file
      happened on Windows. The three-platform parity rule (`MAINTENANCE.md`) is enforced by
      discipline alone with no reviewer — do an actual live run on both to surface what
      Windows-only testing has missed.
- [ ] **Indexer setup guide (honesty check).** The README's "complete my library" promise quietly
      depends on private-tracker/usenet friction the codebase can't automate.
      `TROUBLESHOOTING.md` already documents "no indexers" as expected, not a bug — either write
      a guide that gets someone from zero to one working indexer, or soften the README claim to
      match reality without one.

## P1 — Remaining v0.4.0 items

- [ ] Pinned-URL link check (weekly CI, mirrors dev-sandbox)
- [ ] Apple Silicon support (`darwin_arm64` builds)

## P2 — Discovery & Spotify parity (v0.6.0, blocked until P0 lands)

Closes the gap between "streams your library" (done) and "feels like Spotify" (recommendations,
lyrics, recap) — see `ROADMAP.md`'s `v0.6.0` section for why each item is scoped the way it is.
**Do not start these before the P0 list above is done** — shipping recommendation playlists while
acquisition can silently die unnoticed solves the wrong problem first.

- [ ] **ListenBrainz Discover Weekly / Daily Mix.** Extend the post-config pattern
      (`configure-lidarr.py`) with a Navidrome-side step: register a `LISTENBRAINZ_TOKEN`
      setting, wire Navidrome's native ListenBrainz scrobbling, and install the community
      `navidrome-listenbrainz-daily-playlist` plugin so daily/weekly/exploration playlists
      generate automatically. Native, no Docker.
- [ ] **Synced lyrics backfill.** New `scripts/common/fetch-lyrics.py` — stdlib + the free,
      unauthenticated lrclib.net API — walks `MUSIC_DIR` and writes missing `.lrc` files.
      Idempotent (skip tracks that already have one), same read-modify-write shape as
      `configure-lidarr.py`. Decide whether it runs as a one-shot post-config step or a
      scheduled task per platform (mirrors the Navidrome scan-schedule question).
- [ ] **Document the free yearly recap.** No code — once ListenBrainz scrobbling is wired up
      (previous item), the account's own Year-in-Review page is the recap. Add a README
      pointer once scrobbling ships.
- [ ] **Update `ARCHITECTURE.md`** once the plugin + lyrics script exist: they add a second and
      third component that talk to a service's API, which changes the "only component that
      speaks to a service's API" framing in §5.
- [ ] **Update `MAINTENANCE.md`** with the new script's touchpoints, following the same
      per-script breakdown it already uses for the other three platform scripts.

## Explicitly deferred (tracked, not forgotten)

- [ ] **Auto-acquire recommended-but-missing tracks** (e.g. `re-command`-style: ListenBrainz/
      Last.fm/LLM recs → Soulseek/Deezer download → drop into `MUSIC_DIR`). Real feature, but
      Docker-only plus an LLM/Deezer/Soulseek credential surface — ship as an explicitly opt-in
      appendix, never the default install path. See `ROADMAP.md` Future Vision.
- [ ] **Podcasts.** Navidrome's server doesn't implement the Subsonic podcast endpoints. Folding
      podcasts in changes the product's scope ("music" stack → "media" stack) — revisit
      deliberately per `ROADMAP.md` Future Vision, not as a side effect of this batch.
