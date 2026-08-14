#!/usr/bin/env python3
"""configure-lidarr.py — apply defined settings to a running Lidarr over its REST API.

Idempotent. Uses only the Python standard library (urllib).

Things it does:
  * waits until Lidarr's API is reachable
  * creates the root folder (the shared MUSIC_DIR) if absent
  * registers qBittorrent as the download client if absent
  * enables track renaming
  * registers indexers listed in config/indexers.json (if present)

Usage:
  configure-lidarr.py --settings settings.env [--api-key KEY] [--port N] [--timeout SECONDS]

--settings is required (it carries MUSIC_DIR, QBIT_*, ports). --api-key/--port
override the values in settings (used when the script generated a fresh key).
"""

import argparse
import json
import os
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path


def log(msg: str) -> None:
    print(f"[+] {msg}", flush=True)


def die(msg: str) -> None:
    print(f"[x] {msg}", file=sys.stderr, flush=True)
    sys.exit(1)


# --------------------------------------------------------------- settings --
def load_settings(path: str) -> dict:
    settings: dict = {}
    p = Path(path)
    if not p.exists():
        die(f"settings file not found: {path}")
    for raw in p.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        settings[key.strip()] = val.strip()
    return settings


def expand(val: str) -> str:
    return os.path.expanduser(os.path.expandvars(val)) if val else val


# ------------------------------------------------------------------- http --
class Lidarr:
    def __init__(self, host: str, port: int, api_key: str, timeout: int):
        self.base = f"http://{host}:{port}/api/v1"
        self.api_key = api_key
        self.timeout = timeout

    def _request(self, method: str, path: str, body=None):
        url = self.base + path
        data = None
        headers = {
            "X-Api-Key": self.api_key,
            "Accept": "application/json",
        }
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                raw = resp.read()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", "replace")[:500]
            die(f"{method} {path} -> HTTP {e.code}: {detail}")
        except urllib.error.URLError as e:
            die(f"{method} {path} -> {e.reason}")

    def wait_ready(self, seconds: int) -> None:
        deadline = time.time() + seconds
        while time.time() < deadline:
            try:
                req = urllib.request.Request(
                    self.base + "/system/status",
                    headers={"X-Api-Key": self.api_key},
                )
                with urllib.request.urlopen(req, timeout=5) as resp:
                    if resp.status == 200:
                        return
            except Exception:
                pass
            time.sleep(5)
        die(f"Lidarr API did not come up within {seconds}s at {self.base}")

    def ensure_root_folder(self, music_dir: str) -> None:
        existing = {r.get("path") for r in (self._request("GET", "/rootfolder") or [])}
        if music_dir in existing:
            log(f"root folder already configured: {music_dir}")
            return
        self._request("POST", "/rootfolder", {"path": music_dir})
        log(f"root folder created: {music_dir}")

    def ensure_qbit_client(self, host: str, port: int, user: str, password: str) -> None:
        clients = self._request("GET", "/downloadclient") or []
        if any(c.get("name") == "qBittorrent" for c in clients):
            log("qBittorrent download client already configured")
            return
        body = {
            "enable": True,
            "protocol": "torrent",
            "priority": 1,
            "removeCompletedDownloads": False,
            "removeFailedDownloads": True,
            "name": "qBittorrent",
            "implementation": "QBittorrent",
            "implementationName": "qBittorrent",
            "configContract": "QBittorrentSettings",
            "fields": [
                {"name": "host", "value": host},
                {"name": "port", "value": int(port)},
                {"name": "username", "value": user},
                {"name": "password", "value": password},
                {"name": "category", "value": "lidarr"},
            ],
        }
        self._request("POST", "/downloadclient", body)
        log(f"qBittorrent download client registered ({host}:{port})")

    def enable_naming(self) -> None:
        cfg = self._request("GET", "/config/naming")
        if cfg is None:
            die("GET /config/naming returned nothing")
        cfg.update({
            "renameTracks": True,
            "replaceIllegalCharacters": True,
            "standardTrackFormat": "{Artist Name} - {Album Title} - {track:00} - {Track Title}",
            "multiDiscTrackFormat": "{Artist Name} - {Album Title} - {disc:00}{track:00} - {Track Title}",
            "artistFolderFormat": "{Artist Name}",
            "albumFolderFormat": "{Album Title} ({Release Year})",
        })
        self._request("PUT", "/config/naming", cfg)
        log("track renaming enabled")

    def add_indexers(self, indexers_file: str) -> None:
        if not indexers_file or not os.path.exists(indexers_file):
            log("no config/indexers.json — skipping indexers")
            return
        spec = json.loads(Path(indexers_file).read_text(encoding="utf-8"))
        existing = {i.get("name") for i in (self._request("GET", "/indexer") or [])}
        for entry in spec.get("indexers", []):
            if entry.get("name") in existing:
                log(f"indexer already present: {entry.get('name')}")
                continue
            body = {
                "enableRss": entry.get("enableRss", True),
                "enableAutomaticSearch": entry.get("enableAutomaticSearch", True),
                "enableInteractiveSearch": entry.get("enableInteractiveSearch", True),
                "supportsRss": entry.get("supportsRss", True),
                "supportsSearch": entry.get("supportsSearch", True),
                "protocol": entry.get("protocol", "torrent"),
                "priority": entry.get("priority", 25),
                "name": entry["name"],
                "implementation": entry["implementation"],
                "implementationName": entry.get("implementationName", entry["implementation"]),
                "configContract": entry["configContract"],
                "fields": entry.get("fields", []),
                "downloadClientId": 0,
            }
            self._request("POST", "/indexer", body)
            log(f"indexer added: {entry['name']}")


# ------------------------------------------------------------------ main --
def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--settings", required=True, help="path to settings.env")
    ap.add_argument("--api-key", default=None)
    ap.add_argument("--port", type=int, default=None)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--timeout", type=int, default=300)
    ap.add_argument("--music-dir", default=None, help="override MUSIC_DIR")
    ap.add_argument("--qbit-user", default=None, help="override QBIT_USER")
    ap.add_argument("--qbit-password", default=None, help="override QBIT_PASSWORD")
    ap.add_argument("--qbit-port", type=int, default=None, help="override QBIT_PORT")
    args = ap.parse_args()

    s = load_settings(args.settings)

    music_dir = expand(args.music_dir or s.get("MUSIC_DIR", "") or "")
    if not music_dir:
        die("MUSIC_DIR is empty — set it in settings.env or pass --music-dir")
    api_key = args.api_key or s.get("LIDARR_API_KEY", "")
    if not api_key:
        die("no Lidarr API key given (--api-key or LIDARR_API_KEY)")
    port = args.port or int(s.get("LIDARR_PORT", "8686") or "8686")
    qbit_host = "127.0.0.1"
    qbit_port = args.qbit_port or int(s.get("QBIT_PORT", "8080") or "8080")
    qbit_user = args.qbit_user or s.get("QBIT_USER", "admin") or "admin"
    qbit_password = args.qbit_password or s.get("QBIT_PASSWORD", "")
    if not qbit_password:
        die("QBIT_PASSWORD is empty — set it in settings.env or pass --qbit-password")
    indexers_file = expand(s.get("INDEXERS_FILE", "") or "")
    if not indexers_file:
        candidate = Path("config/indexers.json")
        if candidate.exists():
            indexers_file = str(candidate)

    lidarr = Lidarr(args.host, port, api_key, timeout=args.timeout)
    log(f"waiting for Lidarr at {lidarr.base}")
    lidarr.wait_ready(args.timeout)
    lidarr.ensure_root_folder(music_dir)
    lidarr.ensure_qbit_client(qbit_host, qbit_port, qbit_user, qbit_password)
    lidarr.enable_naming()
    lidarr.add_indexers(indexers_file)
    log("Lidarr configured")


if __name__ == "__main__":
    main()
