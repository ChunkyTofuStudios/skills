"""Unit tests for codemagic_fetch_artifacts.py.

Stdlib-only — no pytest, no extra deps. Run via:

    python3 -m unittest discover \\
        -s skills/symbolize-android-stacktrace/tests -p 'test_*.py'

`tools/run-tests.sh` discovers and runs these alongside the bats suites.
"""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

# Make the bundled script importable as a module for direct function tests.
SCRIPT_DIR = Path(__file__).resolve().parent.parent / "scripts"
sys.path.insert(0, str(SCRIPT_DIR))

import codemagic_fetch_artifacts as cm  # noqa: E402


def _app(app_id: str, name: str, html_url: str | None = None) -> dict:
    """Shape of an entry from `GET /apps`."""
    repo = {"htmlUrl": html_url} if html_url else None
    return {"_id": app_id, "appName": name, "repository": repo}


def _build(build_id: str, version: str, finished_at: str = "2026-01-01T00:00:00Z") -> dict:
    return {
        "_id": build_id,
        "version": version,
        "tag": None,
        "branch": "main",
        "finishedAt": finished_at,
        "artefacts": [
            {"name": "android_native_debug_symbols.zip", "url": "u1", "size": 1},
            {"name": "Demo_42_artifacts.zip",            "url": "u2", "size": 2},
        ],
    }


class GhAvailableTests(unittest.TestCase):
    """`gh` detection caches the result and short-circuits when missing."""

    def setUp(self) -> None:
        # Reset the cached attribute set on the function object.
        cm._gh_available.cache_clear()

    def test_returns_false_when_gh_not_on_path(self) -> None:
        with mock.patch.object(cm.shutil, "which", return_value=None):
            self.assertFalse(cm._gh_available())

    def test_returns_true_when_gh_present(self) -> None:
        with mock.patch.object(cm.shutil, "which", return_value="/usr/local/bin/gh"):
            self.assertTrue(cm._gh_available())

    def test_result_is_cached_after_first_call(self) -> None:
        with mock.patch.object(cm.shutil, "which", return_value="/usr/local/bin/gh") as which:
            cm._gh_available()
            cm._gh_available()
            cm._gh_available()
            which.assert_called_once_with("gh")

    def test_gh_api_short_circuits_when_unavailable(self) -> None:
        """No subprocess call when gh isn't on PATH — that's the whole point of the optional dep."""
        with mock.patch.object(cm.shutil, "which", return_value=None), \
             mock.patch.object(cm.subprocess, "run") as run:
            self.assertIsNone(cm._gh_api("repos/foo/bar/contents/x"))
            run.assert_not_called()

    def test_resolve_application_id_returns_none_without_gh(self) -> None:
        with mock.patch.object(cm.shutil, "which", return_value=None):
            self.assertIsNone(cm._resolve_application_id("https://github.com/foo/bar"))

    def test_resolve_application_id_returns_none_for_non_github_repo(self) -> None:
        with mock.patch.object(cm.shutil, "which", return_value="/usr/local/bin/gh"):
            self.assertIsNone(cm._resolve_application_id("https://gitlab.com/foo/bar"))

    def test_resolve_application_id_returns_none_when_url_missing(self) -> None:
        with mock.patch.object(cm.shutil, "which", return_value="/usr/local/bin/gh"):
            self.assertIsNone(cm._resolve_application_id(None))


class FindAppTests(unittest.TestCase):
    def setUp(self) -> None:
        self.apps = [
            _app("a1", "Pixel Buddy"),
            _app("a2", "Beehive"),
            _app("a3", "Acme"),
        ]
        self.cache = {
            "a1": {"appName": "Pixel Buddy", "repo": None, "package": "com.example.pixelbuddy"},
            "a2": {"appName": "Beehive",     "repo": None, "package": "com.example.beehive"},
            "a3": {"appName": "Acme",        "repo": None, "package": None},
        }

    def test_matches_by_exact_name(self) -> None:
        match = cm.find_app(self.apps, self.cache, "Beehive")
        self.assertEqual(match["_id"], "a2")

    def test_name_match_is_case_insensitive(self) -> None:
        match = cm.find_app(self.apps, self.cache, "PIXEL BUDDY")
        self.assertEqual(match["_id"], "a1")

    def test_matches_by_application_id(self) -> None:
        match = cm.find_app(self.apps, self.cache, "com.example.beehive")
        self.assertEqual(match["_id"], "a2")

    def test_application_id_match_is_case_insensitive(self) -> None:
        match = cm.find_app(self.apps, self.cache, "COM.EXAMPLE.BEEHIVE")
        self.assertEqual(match["_id"], "a2")

    def test_dies_on_no_match(self) -> None:
        with self.assertRaises(SystemExit):
            cm.find_app(self.apps, self.cache, "Nonexistent")

    def test_dies_on_multiple_matches(self) -> None:
        # Force two apps to share a package — a real-world misconfig.
        cache = dict(self.cache)
        cache["a1"] = {**cache["a1"], "package": "com.example.beehive"}
        with self.assertRaises(SystemExit):
            cm.find_app(self.apps, cache, "com.example.beehive")

    def test_unresolved_package_does_not_crash_search(self) -> None:
        # a3 has package=None — searching by name still works.
        match = cm.find_app(self.apps, self.cache, "Acme")
        self.assertEqual(match["_id"], "a3")


class FindBuildTests(unittest.TestCase):
    def setUp(self) -> None:
        self.builds = [
            _build("b3", "2.3.1", "2026-03-01T00:00:00Z"),  # newest first per API
            _build("b2", "2.3.1", "2026-02-01T00:00:00Z"),
            _build("b1", "1.0.0", "2026-01-01T00:00:00Z"),
        ]

    def test_matches_by_exact_version(self) -> None:
        match = cm.find_build(self.builds, "1.0.0")
        self.assertEqual(match["_id"], "b1")

    def test_strips_leading_v_prefix(self) -> None:
        match = cm.find_build(self.builds, "v1.0.0")
        self.assertEqual(match["_id"], "b1")

    def test_multiple_matches_returns_most_recent(self) -> None:
        # The Codemagic API returns newest first; the script picks index 0.
        match = cm.find_build(self.builds, "2.3.1")
        self.assertEqual(match["_id"], "b3")

    def test_dies_on_no_match(self) -> None:
        with self.assertRaises(SystemExit):
            cm.find_build(self.builds, "9.9.9")


class SelectArtifactsTests(unittest.TestCase):
    def test_selects_native_zip_and_flutter_artifacts(self) -> None:
        build = _build("b1", "1.0.0")
        artefacts = cm.select_artifacts(build)
        names = sorted(a["name"] for a in artefacts)
        self.assertEqual(names, ["Demo_42_artifacts.zip", "android_native_debug_symbols.zip"])

    def test_ignores_unrelated_artifacts(self) -> None:
        build = _build("b1", "1.0.0")
        build["artefacts"].append({"name": "release-notes.txt", "url": "u3", "size": 99})
        build["artefacts"].append({"name": "Demo.apk",          "url": "u4", "size": 99})
        names = sorted(a["name"] for a in cm.select_artifacts(build))
        self.assertEqual(names, ["Demo_42_artifacts.zip", "android_native_debug_symbols.zip"])

    def test_flutter_artifacts_regex_requires_trailing_underscore_n(self) -> None:
        build = _build("b1", "1.0.0")
        build["artefacts"] = [
            {"name": "Demo_artifacts.zip",     "url": "u",  "size": 1},  # no _<N>
            {"name": "Demo_v2_artifacts.zip",  "url": "u",  "size": 1},  # _v2 isn't a number
        ]
        self.assertEqual(cm.select_artifacts(build), [])


class FmtDateTests(unittest.TestCase):
    def test_zulu_iso_string_is_normalized_to_utc(self) -> None:
        self.assertEqual(cm.fmt_date("2026-04-27T12:34:56Z"), "2026-04-27T12:34:56+00:00")

    def test_already_offset_iso_passes_through(self) -> None:
        self.assertEqual(cm.fmt_date("2026-04-27T12:34:56+00:00"), "2026-04-27T12:34:56+00:00")

    def test_none_returns_none(self) -> None:
        self.assertIsNone(cm.fmt_date(None))

    def test_garbage_input_returned_as_is(self) -> None:
        # The function is best-effort; unparseable input returns the original
        # string so downstream JSON consumers see the raw value rather than a crash.
        self.assertEqual(cm.fmt_date("not-a-date"), "not-a-date")


class CacheRoundtripTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self._orig_path = cm.APPS_CACHE_PATH
        cm.APPS_CACHE_PATH = Path(self.tmp.name) / "apps.json"

    def tearDown(self) -> None:
        cm.APPS_CACHE_PATH = self._orig_path

    def test_load_returns_empty_dict_when_cache_absent(self) -> None:
        self.assertEqual(cm._load_app_cache(), {})

    def test_save_then_load_roundtrips(self) -> None:
        data = {"a1": {"appName": "X", "repo": None, "package": None}}
        cm._save_app_cache(data)
        self.assertEqual(cm._load_app_cache(), data)

    def test_load_returns_empty_dict_on_corrupt_json(self) -> None:
        cm.APPS_CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
        cm.APPS_CACHE_PATH.write_text("{not json")
        self.assertEqual(cm._load_app_cache(), {})


class FindAppLazyTests(unittest.TestCase):
    """Lazy resolution: only shells out to gh on cache miss + non-name selector."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self._orig_path = cm.APPS_CACHE_PATH
        cm.APPS_CACHE_PATH = Path(self.tmp.name) / "apps.json"
        cm._gh_available.cache_clear()

    def tearDown(self) -> None:
        cm.APPS_CACHE_PATH = self._orig_path

    def test_name_match_does_not_touch_gh(self) -> None:
        # Three apps with no cache, selector hits the first one by display
        # name. The whole point of laziness: don't resolve the others.
        apps = [
            _app("a1", "Pixel Buddy", "https://github.com/foo/pb"),
            _app("a2", "Beehive",     "https://github.com/foo/bh"),
            _app("a3", "Acme",        "https://github.com/foo/ac"),
        ]
        cache: dict = {}
        with mock.patch.object(cm.shutil, "which", return_value="/usr/local/bin/gh"), \
             mock.patch.object(cm, "_resolve_application_id") as resolve:
            match = cm.find_app_lazy(apps, cache, "Pixel Buddy")
        self.assertEqual(match["_id"], "a1")
        resolve.assert_not_called()
        # No app should have been added to the cache by a successful name hit.
        self.assertEqual(cache, {})

    def test_cached_package_match_does_not_touch_gh(self) -> None:
        apps = [
            _app("a1", "Pixel Buddy", "https://github.com/foo/pb"),
            _app("a2", "Beehive",     "https://github.com/foo/bh"),
        ]
        cache = {
            "a2": {"appName": "Beehive", "repo": None, "package": "com.example.beehive"},
        }
        with mock.patch.object(cm.shutil, "which", return_value="/usr/local/bin/gh"), \
             mock.patch.object(cm, "_resolve_application_id") as resolve:
            match = cm.find_app_lazy(apps, cache, "com.example.beehive")
        self.assertEqual(match["_id"], "a2")
        resolve.assert_not_called()

    def test_resolves_lazily_until_first_hit(self) -> None:
        # Three apps, none cached. Selector is a packageId that matches the
        # second app — laziness means gh fires for a1 and a2, but never a3.
        apps = [
            _app("a1", "Pixel Buddy", "https://github.com/foo/pb"),
            _app("a2", "Beehive",     "https://github.com/foo/bh"),
            _app("a3", "Acme",        "https://github.com/foo/ac"),
        ]
        cache: dict = {}
        resolved = {
            "https://github.com/foo/pb": "com.example.pixelbuddy",
            "https://github.com/foo/bh": "com.example.beehive",
            "https://github.com/foo/ac": "com.example.acme",
        }
        with mock.patch.object(cm.shutil, "which", return_value="/usr/local/bin/gh"), \
             mock.patch.object(cm, "_resolve_application_id",
                               side_effect=lambda url: resolved.get(url)) as resolve:
            match = cm.find_app_lazy(apps, cache, "com.example.beehive")
        self.assertEqual(match["_id"], "a2")
        # Stops at the second app, never resolves a3.
        self.assertEqual(resolve.call_count, 2)
        # Resolved entries should be persisted to disk.
        on_disk = cm._load_app_cache()
        self.assertEqual(on_disk["a1"]["package"], "com.example.pixelbuddy")
        self.assertEqual(on_disk["a2"]["package"], "com.example.beehive")
        self.assertNotIn("a3", on_disk)

    def test_dies_clearly_when_gh_missing_and_name_misses(self) -> None:
        apps = [_app("a1", "Pixel Buddy", "https://github.com/foo/pb")]
        with mock.patch.object(cm.shutil, "which", return_value=None):
            with self.assertRaises(SystemExit):
                cm.find_app_lazy(apps, {}, "com.example.notapackage")


class ResolveOneLazilyTests(unittest.TestCase):
    """`_resolve_one_lazily` is idempotent and caches negative results."""

    def setUp(self) -> None:
        cm._gh_available.cache_clear()

    def test_caches_null_when_gh_missing(self) -> None:
        cache: dict = {}
        with mock.patch.object(cm.shutil, "which", return_value=None):
            self.assertIsNone(cm._resolve_one_lazily(cache, _app("a1", "Demo", "https://github.com/foo/bar")))
        self.assertIn("a1", cache)
        self.assertIsNone(cache["a1"]["package"])

    def test_does_not_re_resolve_when_cache_has_entry(self) -> None:
        cache = {"a1": {"appName": "Demo", "repo": "x", "package": "com.cached.pkg"}}
        with mock.patch.object(cm.shutil, "which", return_value="/usr/local/bin/gh"), \
             mock.patch.object(cm, "_resolve_application_id") as resolve:
            pkg = cm._resolve_one_lazily(cache, _app("a1", "Demo", "https://github.com/foo/bar"))
        self.assertEqual(pkg, "com.cached.pkg")
        resolve.assert_not_called()

    def test_caches_negative_result_to_avoid_repeat_lookups(self) -> None:
        cache: dict = {}
        with mock.patch.object(cm.shutil, "which", return_value="/usr/local/bin/gh"), \
             mock.patch.object(cm, "_resolve_application_id", return_value=None) as resolve:
            cm._resolve_one_lazily(cache, _app("a1", "Demo", "https://github.com/foo/bar"))
            cm._resolve_one_lazily(cache, _app("a1", "Demo", "https://github.com/foo/bar"))
        # Second call should hit the cache, not gh.
        self.assertEqual(resolve.call_count, 1)
        self.assertIn("a1", cache)
        self.assertIsNone(cache["a1"]["package"])


if __name__ == "__main__":
    unittest.main()
