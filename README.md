# shinjuku-release

The shared release workflow for apps listed in [Shinjuku](https://github.com/event-horizon-gg/shinjuku), and the script that writes each app's Catalog entry.

It is public so public app repos can use it: GitHub doesn't let a public repo call a workflow stored in a private one. Nothing here is secret. The key that writes the Catalog is an org secret passed in by each app, and the Catalog itself lives in the private `shinjuku-catalog` repo.

On a `v*` tag the workflow builds the app with the app's own command, zips it as `<name>-<version>-mac.zip`, publishes the GitHub Release, and writes the app's entry into the Catalog.

## List an app

The quick way, from a clone of this repo (needs `gh`, and the 1Password CLI `op` for the key):

```bash
scripts/onboard.sh event-horizon-gg/new-app --build-command "./build.sh" --app-path build/NewApp.app
```

It opens a PR in the app's repo with `shinjuku.json` and the release workflow, sets the Catalog and signing secrets on the repo (straight from 1Password to GitHub), and lists what's left: filling in `shinjuku.json` and stamping the version. Add `--dry-run` to see it first, or `--key-file path.pem` without 1Password.

By hand:

1. Add `shinjuku.json` at the app repo's root:

   ```json
   {
     "name": "Heimdall",
     "pitch": "Decide where to start making room on your Mac.",
     "description": "Longer text shown on the app's page in Shinjuku.",
     "accentColor": "#4F7CFF",
     "icon": "Assets/AppIcon.png",
     "screenshots": ["Assets/Screenshots/panel.png", "Assets/Screenshots/settings.png"]
   }
   ```

   `name` is used in the release file name (`Heimdall-2.1.0-mac.zip`), so letters, digits, `.`, `_` and `-` only. Up to 6 screenshots.

2. Add `.github/workflows/release.yml`:

   ```yaml
   name: Release
   on:
     push:
       tags: ["v*"]
   jobs:
     release:
       uses: event-horizon-gg/shinjuku-release/.github/workflows/release.yml@main
       with:
         build-command: ./build.sh            # must produce the .app below
         app-path: build/Heimdall.app
       secrets:
         catalog-app-id: ${{ secrets.SHINJUKU_CATALOG_APP_ID }}
         catalog-app-key: ${{ secrets.SHINJUKU_CATALOG_APP_KEY }}
   ```

3. Make the build set `CFBundleShortVersionString` to `$SHINJUKU_VERSION` (the tag without the `v`). The workflow refuses to publish when they differ, because Shinjuku reads the version from the installed app.

4. Release: `git tag v2.1.0 && git push origin v2.1.0`. A tag with a suffix (`v2.1.0-beta.1`) becomes a Beta Release.

## Stable signing

Ad-hoc signatures change on every build, so macOS asks again for Keychain items after each update. To stop that, sign every release with one fixed identity:

```bash
scripts/make-signing-identity.sh event-horizon-gg/shinjuku
```

It creates a self-signed "Event Horizon Releases" certificate and sets `SHINJUKU_SIGNING_P12` and `SHINJUKU_SIGNING_PASSWORD` on the repo. Pass them through in the app's release workflow:

```yaml
    secrets:
      catalog-app-id: ${{ secrets.SHINJUKU_CATALOG_APP_ID }}
      catalog-app-key: ${{ secrets.SHINJUKU_CATALOG_APP_KEY }}
      signing-p12: ${{ secrets.SHINJUKU_SIGNING_P12 }}
      signing-password: ${{ secrets.SHINJUKU_SIGNING_PASSWORD }}
```

Keep the `.p12` and its password in 1Password; add the same identity to another repo with `--reuse`. It's not notarization: Gatekeeper still asks on first open.

## iPhone apps

Shinjuku doesn't install iPhone apps; it runs them in the iOS Simulator so you can try a release without a device. Pass `platform: ios` and build for the Simulator:

```yaml
    with:
      platform: ios
      build-command: >-
        xcodebuild -project Spotter.xcodeproj -scheme Spotter -configuration Release
        -destination 'generic/platform=iOS Simulator' -derivedDataPath build
        CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- MARKETING_VERSION=$SHINJUKU_VERSION build
      app-path: build/Build/Products/Release-iphonesimulator/Spotter.app
```

The release then carries `<name>-<version>-ios-simulator.zip`, and the Catalog entry gets `"platform": "ios"`. No signing secrets are needed. `onboard.sh --platform ios` writes this for you.

## Newer Swift than GitHub's runners

GitHub's macOS runners ship Xcode 26. If your app needs a newer Swift compiler (Mimir does), add `swift-version: "6.4.2"` under `with:` in its release workflow. The workflow installs that toolchain from swift.org before building.

## Entry format

| Field | Meaning |
|---|---|
| `id` | Repo name, lowercased |
| `repo` | `owner/name` the Releases come from |
| `name` | Display name, and the release file prefix |
| `bundleId`, `appFile` | Read from the built app |
| `pitch`, `description`, `accentColor` | From `shinjuku.json` |
| `icon`, `screenshots` | Copied into `apps/<id>/` |
| `delisted` | Optional; set by hand or from Shinjuku |

## Tests

```bash
python3 -m unittest discover -s tests
```
