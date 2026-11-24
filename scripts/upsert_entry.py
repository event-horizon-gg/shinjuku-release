#!/usr/bin/env python3
"""Write one app's entry into the Shinjuku Catalog.

Called by the shared release workflow after a Release is published. Says which
apps exist and how they look; never which versions (those live on GitHub
Releases). A `delisted` mark set by hand or from Shinjuku is always preserved.
"""
import argparse
import json
import pathlib
import re
import shutil
import sys

ALLOWED_IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".icns", ".heic", ".webp"}
HEX_COLOR = re.compile(r"^#[0-9A-Fa-f]{6}$")
NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


def fail(message: str) -> None:
    print(f"::error::{message}", file=sys.stderr)
    sys.exit(1)


def copy_image(source_root: pathlib.Path, relative: str, destination: pathlib.Path) -> str:
    source = (source_root / relative).resolve()
    if source_root.resolve() not in source.parents:
        fail(f"{relative} points outside the repository")
    if not source.is_file():
        fail(f"{relative} does not exist")
    suffix = source.suffix.lower()
    if suffix not in ALLOWED_IMAGE_SUFFIXES:
        fail(f"{relative}: images must be one of {sorted(ALLOWED_IMAGE_SUFFIXES)}")
    destination = destination.with_suffix(suffix)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
    return destination.as_posix()


def build_entry(args: argparse.Namespace, catalog_dir: pathlib.Path) -> dict:
    metadata_path = pathlib.Path(args.metadata)
    if not metadata_path.is_file():
        fail(f"{metadata_path} is missing; every app needs one (see shinjuku-catalog README)")
    metadata = json.loads(metadata_path.read_text())
    source_root = metadata_path.parent

    name = metadata.get("name")
    if not isinstance(name, str) or not NAME.match(name):
        fail("shinjuku.json: `name` is required and may only contain letters, digits, '.', '_' and '-' (it is used in the asset file name)")
    pitch = metadata.get("pitch", "")
    if len(pitch) > 120:
        fail("shinjuku.json: `pitch` must be 120 characters or fewer")
    accent = metadata.get("accentColor")
    if accent is not None and not HEX_COLOR.match(accent):
        fail("shinjuku.json: `accentColor` must look like #RRGGBB")

    app_id = args.repo.split("/")[-1].lower()
    app_dir = catalog_dir / "apps" / app_id
    shutil.rmtree(app_dir, ignore_errors=True)

    entry = {
        "id": app_id,
        "repo": args.repo,
        "name": name,
        "bundleId": args.bundle_id,
        "appFile": args.app_file,
        "pitch": pitch,
        "description": metadata.get("description", ""),
    }
    if args.platform != "mac":
        entry["platform"] = args.platform  # absent means a Mac app, so older Shinjukus still read the Catalog
    if accent:
        entry["accentColor"] = accent
    if metadata.get("icon"):
        icon = copy_image(source_root, metadata["icon"], app_dir / "icon")
        entry["icon"] = pathlib.Path(icon).relative_to(catalog_dir).as_posix()
    screenshots = metadata.get("screenshots", [])
    if len(screenshots) > 6:
        fail("shinjuku.json: at most 6 screenshots")
    entry["screenshots"] = [
        pathlib.Path(copy_image(source_root, shot, app_dir / "screenshots" / f"{index + 1}")).relative_to(catalog_dir).as_posix()
        for index, shot in enumerate(screenshots)
    ]
    return entry


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--catalog-dir", required=True)
    parser.add_argument("--metadata", required=True)
    parser.add_argument("--repo", required=True, help="owner/name of the app's repository")
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--app-file", required=True, help="e.g. Heimdall.app")
    parser.add_argument("--platform", choices=["mac", "ios"], default="mac")
    args = parser.parse_args()

    catalog_dir = pathlib.Path(args.catalog_dir)
    catalog_path = catalog_dir / "catalog.json"
    catalog = json.loads(catalog_path.read_text())
    apps = catalog.setdefault("apps", [])

    entry = build_entry(args, catalog_dir)
    existing = next((app for app in apps if app["id"] == entry["id"]), None)
    if existing is not None:
        if existing.get("delisted"):
            entry["delisted"] = True  # never re-listed by a release
        apps.remove(existing)
    apps.append(entry)
    apps.sort(key=lambda app: app["name"].lower())

    catalog_path.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n")
    state = "delisted (kept delisted)" if entry.get("delisted") else "listed"
    print(f"{entry['name']} is {state} in the Catalog")


if __name__ == "__main__":
    main()
