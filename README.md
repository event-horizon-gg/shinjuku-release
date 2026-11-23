# shinjuku-release

The shared release workflow for apps listed in [Shinjuku](https://github.com/event-horizon-gg/shinjuku), and the script that writes each app's Catalog entry.

It is public so public app repos can use it: GitHub doesn't let a public repo call a workflow stored in a private one. Nothing here is secret. The key that writes the Catalog is an org secret passed in by each app, and the Catalog itself lives in the private `shinjuku-catalog` repo.

On a `v*` tag the workflow builds the app with the app's own command, zips it as `<name>-<version>-mac.zip`, publishes the GitHub Release, and writes the app's entry into the Catalog.

## List an app

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
