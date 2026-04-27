#!/usr/bin/env python3
"""Fetch Android symbol artifacts from Codemagic. Designed for AI agent use.

Three modes (no interactive prompts):

  1) No flags:                              list all visible apps.
  2) --app <name|package>:                  list Android builds for that app.
  3) --app <name|package> --build <ver>:    download both Android symbol zips.

In every mode, machine-readable JSON is printed to stdout. Human-readable
status / progress messages go to stderr.

Examples:
  codemagic_fetch_artifacts.py
  codemagic_fetch_artifacts.py --app Beehive
  codemagic_fetch_artifacts.py --app com.chunkytofustudios.beehive
  codemagic_fetch_artifacts.py --app Beehive --build 2.3.1
  codemagic_fetch_artifacts.py --app "Pixel Buddy" --build 3.4.7

Selectors:
  --app <value>     App name (case-insensitive exact match against appName)
                    *or* Android applicationId / iOS bundleId (e.g.
                    "com.chunkytofustudios.beehive"). applicationId lookup
                    is lazy — it's only triggered when the selector doesn't
                    match a display name and the cache doesn't already know
                    the package. Resolved values are cached per-app.
  --build <version> Build version string, e.g. "2.3.1" (leading "v" tolerated).
                    When multiple finished Android builds share a version,
                    the most recent one is selected.

Output (stdout):
  No flags:               {"apps": [{"appId", "appName", "package", "repo"}, ...]}
  --app:                  {"app": {...}, "builds": [{"buildId","version", ...}]}
  --app --build:          {"app": {...}, "build": {...}, "files": [...]}

  In list-apps mode, `package` is whatever's in the cache — typically null on
  first run. Pass `--app <appName>` (or `--app <applicationId>` once gh is
  authenticated) to trigger resolution for the apps it actually visits.

Caches:
  ~/.cache/codemagic-fetch-artifacts/codemagic-apps.json
      appId -> {appName, package, repo}  (package resolved via `gh api`,
      lazily — only entries whose package was actually requested are filled)
  ~/.cache/codemagic-fetch-artifacts/codemagic/<appId>/<buildId>/
      Downloaded zip artifacts (cache hits verified by size match).

Auth: the Codemagic API key is resolved in this order —
  1. CODEMAGIC_API_KEY env var.
  2. A file named `.codemagic-api-key` found by walking up from the current
     working directory (search stops at the directory containing `.git`,
     so the lookup never crosses repo boundaries). Contents are the key
     verbatim, with surrounding whitespace stripped. Plaintext on disk —
     only check it in if the repo is private and the team accepts the risk.

The `gh` CLI is optional — when present and authenticated, `--app` also
accepts the Android applicationId (resolved from the repo's gradle file).
Without `gh`, select apps by their Codemagic display name (the no-flag
`apps[].appName` field).
"""

from __future__ import annotations

import argparse
import base64
import functools
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import NoReturn

API_BASE = "https://api.codemagic.io"
NATIVE_SYMBOLS_NAME = "android_native_debug_symbols.zip"
FLUTTER_ARTIFACTS_RE = re.compile(r"^.+_\d+_artifacts\.zip$")
# Optional R8 mapping file — only present when minification is on. When
# available, the symbolizer can deobfuscate user-app Java frames. Absent
# is fine (apps without R8/Proguard).
MAPPING_NAME = "mapping.txt"
ROOT_CACHE_DIR = Path.home() / ".cache" / "codemagic-fetch-artifacts"
DOWNLOADS_CACHE_DIR = ROOT_CACHE_DIR / "codemagic"
APPS_CACHE_PATH = ROOT_CACHE_DIR / "codemagic-apps.json"
BUILDS_PER_APP = 50

GITHUB_REPO_RE = re.compile(r"https://github\.com/([^/]+)/([^/]+?)(?:\.git)?/?$")
APPLICATION_ID_RE = re.compile(
    r"""applicationId\s*[=\s]\s*["']([a-zA-Z0-9_.]+)["']"""
)


# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

def info(msg: str) -> None:
    print(f"[INFO] {msg}", file=sys.stderr, flush=True)


def warn(msg: str) -> None:
    print(f"[WARN] {msg}", file=sys.stderr, flush=True)


def die(msg: str, code: int = 1) -> NoReturn:
    print(f"[ERROR] {msg}", file=sys.stderr, flush=True)
    sys.exit(code)


def emit(payload: dict) -> None:
    """Print the result as JSON to stdout — the only thing on stdout."""
    json.dump(payload, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")


def fmt_date(iso: str | None) -> str | None:
    if not iso:
        return None
    try:
        dt = datetime.fromisoformat(iso.replace("Z", "+00:00"))
        return dt.astimezone(timezone.utc).isoformat()
    except ValueError:
        return iso


# ---------------------------------------------------------------------------
# Codemagic API
# ---------------------------------------------------------------------------

API_KEY_FILENAME = ".codemagic-api-key"


def _find_key_file(start: Path) -> Path | None:
    """Walk up from `start` looking for `.codemagic-api-key`.

    Stops at (and includes) the first directory containing `.git`, then
    returns. This keeps the lookup scoped to a single repo, so a stray
    key file in a parent directory can never be picked up by a sibling
    project.
    """
    for d in [start, *start.parents]:
        candidate = d / API_KEY_FILENAME
        if candidate.is_file():
            return candidate
        if (d / ".git").exists():
            return None
    return None


@functools.lru_cache(maxsize=1)
def _token() -> str:
    env = os.environ.get("CODEMAGIC_API_KEY")
    if env and env.strip():
        return env.strip()
    key_file = _find_key_file(Path.cwd().resolve())
    if key_file:
        contents = key_file.read_text().strip()
        if contents:
            return contents
        die(f"{key_file} is empty.")
    die(
        "Codemagic API key not found. Set CODEMAGIC_API_KEY env var, or "
        f"create a `{API_KEY_FILENAME}` file at the repo root containing "
        "the key (plaintext)."
    )


def api_get(path: str) -> dict:
    req = urllib.request.Request(
        f"{API_BASE}{path}", headers={"x-auth-token": _token()}
    )
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        die(f"Codemagic API {e.code} on {path}: {e.read().decode(errors='replace')}")


def list_apps() -> list[dict]:
    apps = api_get("/apps").get("applications", [])
    return sorted(apps, key=lambda a: a.get("appName", "").lower())


def list_android_builds(app_id: str, limit: int = BUILDS_PER_APP) -> list[dict]:
    qs = urllib.parse.urlencode({"appId": app_id, "limit": limit})
    builds = api_get(f"/builds?{qs}").get("builds", [])
    out = []
    for b in builds:
        if b.get("status") != "finished":
            continue
        artefact_names = {a["name"] for a in b.get("artefacts", [])}
        if NATIVE_SYMBOLS_NAME not in artefact_names:
            continue
        out.append(b)
    return out


# ---------------------------------------------------------------------------
# applicationId resolution (cached; via `gh api`)
# ---------------------------------------------------------------------------

@functools.cache
def _gh_available() -> bool:
    """True iff the `gh` CLI is on PATH. Cached for the life of the process."""
    return shutil.which("gh") is not None


def _gh_api(path: str) -> dict | list | None:
    if not _gh_available():
        return None
    r = subprocess.run(
        ["gh", "api", path],
        capture_output=True, text=True, check=False,
    )
    if r.returncode != 0:
        return None
    return json.loads(r.stdout) if r.stdout else None


def _resolve_application_id(html_url: str | None) -> str | None:
    """Resolve applicationId from the project's gradle file via `gh api`.

    Returns None if `gh` is unavailable, the repo can't be parsed, or the
    gradle file doesn't declare an `applicationId`. Callers should treat a
    None result as "select this app by display name instead".
    """
    if not _gh_available() or not html_url:
        return None
    m = GITHUB_REPO_RE.match(html_url)
    if not m:
        return None
    owner, repo = m.group(1), m.group(2)
    for fname in ("android/app/build.gradle.kts", "android/app/build.gradle"):
        meta = _gh_api(f"repos/{owner}/{repo}/contents/{fname}")
        if not isinstance(meta, dict) or "content" not in meta:
            continue
        try:
            text = base64.b64decode(meta["content"]).decode("utf-8", errors="replace")
        except (ValueError, KeyError):
            continue
        if hit := APPLICATION_ID_RE.search(text):
            return hit.group(1)
    return None


def _load_app_cache() -> dict:
    if APPS_CACHE_PATH.exists():
        try:
            return json.loads(APPS_CACHE_PATH.read_text())
        except json.JSONDecodeError:
            return {}
    return {}


def _save_app_cache(data: dict) -> None:
    APPS_CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
    APPS_CACHE_PATH.write_text(json.dumps(data, indent=2, sort_keys=True))


def _resolve_one_lazily(cache: dict, app: dict) -> str | None:
    """Resolve and cache one app's applicationId. Idempotent.

    Returns the package (or None — meaning gh missing, repo unparseable,
    or no `applicationId` in the gradle file). The result, including
    None, is cached so we never shell out to gh twice for the same app.
    """
    app_id = app["_id"]
    if app_id in cache and "package" in cache[app_id]:
        return cache[app_id]["package"]

    repo = (app.get("repository") or {}).get("htmlUrl")
    if _gh_available():
        info(f"Resolving applicationId for {app.get('appName')} ...")
        package = _resolve_application_id(repo)
    else:
        package = None

    cache[app_id] = {
        "appName": app.get("appName"),
        "repo": repo,
        "package": package,
    }
    return package


# ---------------------------------------------------------------------------
# Selectors
# ---------------------------------------------------------------------------

def _app_summary(a: dict, cache: dict[str, dict]) -> dict:
    entry = cache.get(a["_id"], {})
    return {
        "appId": a["_id"],
        "appName": a.get("appName"),
        "package": entry.get("package"),
        "repo": (a.get("repository") or {}).get("htmlUrl"),
    }


def _build_summary(b: dict) -> dict:
    return {
        "buildId": b["_id"],
        "version": b.get("version"),
        "tag": b.get("tag"),
        "branch": b.get("branch"),
        "finishedAt": fmt_date(b.get("finishedAt")),
        "artefacts": sorted(a["name"] for a in b.get("artefacts", [])),
    }


def _match_in_cache(apps: list[dict], cache: dict[str, dict], selector: str) -> list[dict]:
    """Cache-only lookup. Returns 0..N matching apps. No network."""
    needle = selector.lower()
    matches = []
    for a in apps:
        if (a.get("appName") or "").lower() == needle:
            matches.append(a)
            continue
        package = (cache.get(a["_id"], {}).get("package") or "")
        if package and (package == selector or package.lower() == needle):
            matches.append(a)
    return matches


def find_app(apps: list[dict], cache: dict[str, dict], selector: str) -> dict:
    """Match by appName (case-insensitive exact) OR applicationId (exact).

    Cache-only — does not shell out to gh. Use `find_app_lazy` to also
    permit on-demand applicationId resolution for entries the cache hasn't
    seen yet.
    """
    matches = _match_in_cache(apps, cache, selector)
    if not matches:
        known = ", ".join(
            f"{a.get('appName')!r} ({cache.get(a['_id'], {}).get('package') or '?'})"
            for a in apps
        )
        die(f"No app matched {selector!r}. Known: {known}")
    if len(matches) > 1:
        die(f"Multiple apps matched {selector!r}: {[a.get('appName') for a in matches]}")
    return matches[0]


def find_app_lazy(apps: list[dict], cache: dict[str, dict], selector: str) -> dict:
    """Like `find_app`, but resolves applicationId on demand for cache misses.

    Strategy:
      1. Match by display name (free).
      2. Match by already-cached applicationId (free).
      3. Only if 1 + 2 miss: resolve unresolved apps one at a time via `gh`,
         stopping the moment we get a hit. Persist each new entry as we go.

    Most invocations stop at step 1, so on a clean cache the only `gh` calls
    happen when the user passed an applicationId we haven't resolved yet.
    """
    matches = _match_in_cache(apps, cache, selector)
    if len(matches) == 1:
        return matches[0]
    if len(matches) > 1:
        die(f"Multiple apps matched {selector!r}: {[a.get('appName') for a in matches]}")

    needle = selector.lower()
    if not _gh_available():
        die(
            f"No app matched {selector!r} by display name, and `gh` is not on "
            f"PATH so applicationId lookup is unavailable. Either install gh "
            f"and `gh auth login`, or select the app by its Codemagic display "
            f"name (run with no flags to list display names)."
        )

    dirty = False
    for app in apps:
        if app["_id"] in cache and "package" in cache[app["_id"]]:
            continue  # already attempted; skip to avoid re-shelling out
        pkg = _resolve_one_lazily(cache, app)
        dirty = True
        if pkg and (pkg == selector or pkg.lower() == needle):
            _save_app_cache(cache)
            return app

    if dirty:
        _save_app_cache(cache)

    # No match after exhausting unresolved entries. `find_app` will produce
    # the diagnostic with the now-fully-populated cache.
    return find_app(apps, cache, selector)


def find_build(builds: list[dict], version: str) -> dict:
    """Find the most recent Android build with the given version string."""
    target = version.lstrip("vV")  # tolerate "v2.3.1"
    matches = [b for b in builds if (b.get("version") or "") == target]
    if not matches:
        available = sorted(
            {b.get("version") for b in builds if b.get("version")},
            reverse=True,
        )
        die(
            f"No Android build with version {version!r}. "
            f"Available (most recent first): {available[:10]}"
        )
    if len(matches) > 1:
        warn(
            f"{len(matches)} Android builds match version {version!r}; "
            f"selecting the most recent."
        )
    # The Codemagic API returns builds newest-first.
    return matches[0]


# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------

def download(url: str, dest: Path, expected_size: int | None) -> bool:
    """Download `url` to `dest` unless a same-size file already exists.

    Returns True if a network download happened, False if cache was reused.
    """
    if dest.exists() and (expected_size is None or dest.stat().st_size == expected_size):
        info(f"Cached: {dest.name} ({dest.stat().st_size:,} bytes)")
        return False

    tmp = dest.with_suffix(dest.suffix + ".part")
    info(f"Downloading {dest.name} ...")
    req = urllib.request.Request(url, headers={"x-auth-token": _token()})
    with urllib.request.urlopen(req) as r, open(tmp, "wb") as f:
        shutil.copyfileobj(r, f, length=1 << 20)
    tmp.replace(dest)
    info(f"  -> {dest} ({dest.stat().st_size:,} bytes)")
    return True


def select_artifacts(build: dict) -> list[dict]:
    out = []
    for a in build.get("artefacts", []):
        name = a["name"]
        if (
            name == NATIVE_SYMBOLS_NAME
            or name == MAPPING_NAME
            or FLUTTER_ARTIFACTS_RE.match(name)
        ):
            out.append(a)
    return out


# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------

def mode_list_apps() -> None:
    apps = list_apps()
    cache = _load_app_cache()
    info(f"Found {len(apps)} app(s).")
    emit({"apps": [_app_summary(a, cache) for a in apps]})


def mode_list_builds(app_selector: str) -> None:
    apps = list_apps()
    cache = _load_app_cache()
    app = find_app_lazy(apps, cache, app_selector)
    info(f"Listing finished Android builds for {app['appName']} ({app['_id']}) ...")
    builds = list_android_builds(app["_id"])
    info(f"Found {len(builds)} finished Android build(s).")
    emit({
        "app": _app_summary(app, cache),
        "builds": [_build_summary(b) for b in builds],
    })


def mode_download(app_selector: str, build_selector: str) -> None:
    apps = list_apps()
    cache = _load_app_cache()
    app = find_app_lazy(apps, cache, app_selector)
    builds = list_android_builds(app["_id"])
    build = find_build(builds, build_selector)

    artefacts = select_artifacts(build)
    if not artefacts:
        die(f"Build {build['_id']} has no Android symbol artefacts.")

    found_names = {a["name"] for a in artefacts}
    if NATIVE_SYMBOLS_NAME not in found_names:
        warn(f"{NATIVE_SYMBOLS_NAME} missing in artefacts; got {sorted(found_names)}")
    if not any(FLUTTER_ARTIFACTS_RE.match(n) for n in found_names):
        warn(f"No <AppName>_<N>_artifacts.zip in artefacts; got {sorted(found_names)}")

    out_dir = DOWNLOADS_CACHE_DIR / app["_id"] / build["_id"]
    out_dir.mkdir(parents=True, exist_ok=True)

    files = []
    for art in sorted(artefacts, key=lambda a: a["name"]):
        dest = out_dir / art["name"]
        cached = not download(art["url"], dest, expected_size=art.get("size"))
        files.append({
            "name": art["name"],
            "path": str(dest),
            "size": dest.stat().st_size,
            "cached": cached,
        })

    info(
        f"Ready: {app['appName']} v{build.get('version','?')} "
        f"(buildId={build['_id']}) — {len(files)} file(s) at {out_dir}"
    )
    emit({
        "app": _app_summary(app, cache),
        "build": _build_summary(build),
        "cacheDir": str(out_dir),
        "files": files,
    })


# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------

def main() -> None:
    doc = __doc__ or ""
    p = argparse.ArgumentParser(
        description=doc.splitlines()[0] if doc else "",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=doc.split("\n\n", 1)[1] if "\n\n" in doc else "",
    )
    p.add_argument("--app", "-a",
                   help="App name (case-insensitive) or applicationId.")
    p.add_argument("--build", "-b", help='Version string, e.g. "2.3.1".')
    args = p.parse_args()

    if args.build and not args.app:
        die("--build requires --app.")

    if not args.app:
        mode_list_apps()
    elif not args.build:
        mode_list_builds(args.app)
    else:
        mode_download(args.app, args.build)


if __name__ == "__main__":
    main()
