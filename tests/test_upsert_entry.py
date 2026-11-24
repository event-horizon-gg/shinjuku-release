import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "upsert_entry.py"


def run(catalog: pathlib.Path, app: pathlib.Path, repo="event-horizon-gg/heimdall", extra=()):
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--catalog-dir", str(catalog), "--metadata", str(app / "shinjuku.json"),
         "--repo", repo, "--bundle-id", "dev.example.heimdall", "--app-file", "Heimdall.app", *extra],
        capture_output=True, text=True,
    )


class UpsertEntryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp())
        self.catalog = self.tmp / "catalog"
        (self.catalog / "apps").mkdir(parents=True)
        (self.catalog / "catalog.json").write_text('{"schemaVersion": 1, "apps": []}')
        self.app = self.tmp / "app"
        (self.app / "art").mkdir(parents=True)
        (self.app / "art" / "icon.png").write_bytes(b"png")
        (self.app / "art" / "one.png").write_bytes(b"png")
        (self.app / "shinjuku.json").write_text(json.dumps({
            "name": "Heimdall", "pitch": "Make room on your Mac", "accentColor": "#3366FF",
            "icon": "art/icon.png", "screenshots": ["art/one.png"],
        }))

    def entries(self):
        return json.loads((self.catalog / "catalog.json").read_text())["apps"]

    def test_adds_entry_with_copied_images(self):
        result = run(self.catalog, self.app)
        self.assertEqual(result.returncode, 0, result.stderr)
        [entry] = self.entries()
        self.assertEqual(entry["id"], "heimdall")
        self.assertEqual(entry["icon"], "apps/heimdall/icon.png")
        self.assertEqual(entry["screenshots"], ["apps/heimdall/screenshots/1.png"])
        self.assertTrue((self.catalog / entry["icon"]).is_file())
        self.assertNotIn("delisted", entry)

    def test_mac_entries_have_no_platform_field(self):
        run(self.catalog, self.app)
        self.assertNotIn("platform", self.entries()[0])

    def test_ios_entries_are_marked(self):
        result = run(self.catalog, self.app, extra=("--platform", "ios"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.entries()[0]["platform"], "ios")

    def test_release_never_relists_a_delisted_app(self):
        run(self.catalog, self.app)
        catalog = json.loads((self.catalog / "catalog.json").read_text())
        catalog["apps"][0]["delisted"] = True
        (self.catalog / "catalog.json").write_text(json.dumps(catalog))
        run(self.catalog, self.app)
        self.assertTrue(self.entries()[0]["delisted"])

    def test_rejects_images_outside_repo(self):
        (self.app / "shinjuku.json").write_text(json.dumps({"name": "Heimdall", "icon": "../catalog/catalog.json"}))
        self.assertNotEqual(run(self.catalog, self.app).returncode, 0)

    def test_rejects_names_unsafe_for_asset_file(self):
        (self.app / "shinjuku.json").write_text(json.dumps({"name": "My App"}))
        self.assertNotEqual(run(self.catalog, self.app).returncode, 0)


if __name__ == "__main__":
    unittest.main()
