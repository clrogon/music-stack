# TODO

Near-term, actionable checklist. This is the working list; `ROADMAP.md` is the versioned,
narrative form of the same priorities (see its `v0.6.0` entry for this batch), and
`CHANGELOG.md` records what actually shipped. Check items off here as they land, then fold the
summary into `CHANGELOG.md` under `Unreleased` the way every prior change has been.

## Discovery & Spotify parity (v0.6.0)

Closes the gap between "streams your library" (done) and "feels like Spotify" (recommendations,
lyrics, recap) — see the design notes in `ROADMAP.md`'s `v0.6.0` section for why each item is
scoped the way it is.

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

## Carried over from v0.4.0 (already in ROADMAP.md, unchanged by this analysis)

- [ ] Windows qBittorrent auto-start (Scheduled Task or NSSM supervision)
- [ ] Pinned-URL link check (weekly CI, mirrors dev-sandbox)
- [ ] Apple Silicon support (`darwin_arm64` builds)
- [ ] Smoke-test script (ports listening, Lidarr health, qBittorrent WebUI auth)
