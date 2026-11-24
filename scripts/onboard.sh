#!/usr/bin/env bash
# Lists a Mac app in Shinjuku: opens a PR in the app's repo that adds shinjuku.json and
# the release workflow, and sets the two Catalog secrets on the repo.
#
#   scripts/onboard.sh event-horizon-gg/new-app \
#     --build-command "./build.sh" --app-path build/NewApp.app
#
# The Catalog App's private key is read from 1Password ("Shinjuku Catalog key" document,
# via the `op` CLI) or from --key-file. It is piped straight into GitHub, never written to disk.
#
# Options:
#   --build-command CMD  Command that builds the .app (runs with $SHINJUKU_VERSION set)
#   --app-path PATH      Where the built .app ends up, relative to the repo root
#   --name NAME          Display name and release file prefix (default: repo name, capitalized)
#   --app-id ID          Catalog App's App ID (default: $SHINJUKU_CATALOG_APP_ID, else 5895717)
#   --op-item TITLE      1Password document holding the key (default: "Shinjuku Catalog key")
#   --key-file PATH      Read the key from this file instead of 1Password
#   --signing-p12 PATH   The Event Horizon Releases identity (.p12); asks for its password.
#                        Default: 1Password document "Event Horizon Releases" and that item's password.
#   --skip-signing       Leave releases ad-hoc signed (macOS re-asks for Keychain access each update)
#   --skip-secrets       Don't touch the repo's secrets
#   --dry-run            Prepare the branch locally and show it; push and set nothing
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

repo="" build_command="" app_path="" name=""
app_id="${SHINJUKU_CATALOG_APP_ID:-5895717}"
op_item="Shinjuku Catalog key" key_file="" skip_secrets=false dry_run=false
signing_p12="" signing_item="Event Horizon Releases" skip_signing=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-command) build_command="$2"; shift 2 ;;
    --app-path) app_path="$2"; shift 2 ;;
    --name) name="$2"; shift 2 ;;
    --app-id) app_id="$2"; shift 2 ;;
    --op-item) op_item="$2"; shift 2 ;;
    --key-file) key_file="$2"; shift 2 ;;
    --signing-p12) signing_p12="$2"; shift 2 ;;
    --skip-signing) skip_signing=true; shift ;;
    --skip-secrets) skip_secrets=true; shift ;;
    --dry-run) dry_run=true; shift ;;
    -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "unknown option $1" ;;
    *) [[ -z "$repo" ]] || die "only one repo, please"; repo="$1"; shift ;;
  esac
done

[[ "$repo" == */* ]] || die "give the repo as owner/name, e.g. event-horizon-gg/new-app"
command -v gh >/dev/null || die "needs the GitHub CLI (gh)"
gh repo view "$repo" --json name >/dev/null 2>&1 || die "can't see $repo with your gh login"

repo_name="${repo#*/}"
if [[ -z "$name" ]]; then
  name="$(tr '[:lower:]' '[:upper:]' <<<"${repo_name:0:1}")${repo_name:1}"
fi
[[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || die "name '$name' can only use letters, digits, '.', '_' and '-' (pass --name)"
[[ -n "$build_command" ]] || build_command="./build.sh  # TODO: the command that builds $name.app"
[[ -n "$app_path" ]] || app_path="build/$name.app"

# Check the key source before changing anything, so a missing key doesn't leave a half-done repo.
if ! $skip_secrets && ! $dry_run; then
  if [[ -n "$key_file" ]]; then
    [[ -r "$key_file" ]] || die "can't read $key_file"
  else
    command -v op >/dev/null || die "needs the 1Password CLI (brew install 1password-cli, then turn on 'Integrate with 1Password CLI' in 1Password → Settings → Developer), or pass --key-file"
    op document get "$op_item" >/dev/null || die "couldn't read '$op_item' from 1Password"
  fi
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
gh repo clone "$repo" "$work/repo" -- --quiet
cd "$work/repo"
branch="shinjuku-onboard"
git checkout -q -b "$branch"

added=()
if [[ ! -f shinjuku.json ]]; then
  cat > shinjuku.json <<EOF
{
  "name": "$name",
  "pitch": "TODO: one line shown under the name in Shinjuku.",
  "description": "TODO: a few sentences for the app's page in Shinjuku.",
  "accentColor": "#4F7CFF",
  "icon": "TODO/path/to/AppIcon.png",
  "screenshots": []
}
EOF
  added+=(shinjuku.json)
fi

workflow=.github/workflows/shinjuku-release.yml
if [[ ! -f "$workflow" ]]; then
  mkdir -p .github/workflows
  cat > "$workflow" <<EOF
name: Shinjuku release
on:
  push:
    tags: ["v*"]
jobs:
  release:
    permissions:
      contents: write
    uses: event-horizon-gg/shinjuku-release/.github/workflows/release.yml@main
    with:
      build-command: $build_command
      app-path: $app_path
    secrets:
      catalog-app-id: \${{ secrets.SHINJUKU_CATALOG_APP_ID }}
      catalog-app-key: \${{ secrets.SHINJUKU_CATALOG_APP_KEY }}
      signing-p12: \${{ secrets.SHINJUKU_SIGNING_P12 }}
      signing-password: \${{ secrets.SHINJUKU_SIGNING_PASSWORD }}
EOF
  added+=("$workflow")
fi

pr_url=""
if [[ ${#added[@]} -eq 0 ]]; then
  echo "$repo already has shinjuku.json and $workflow; no PR needed."
else
  git add "${added[@]}"
  git commit -q -m "List in Shinjuku

Adds shinjuku.json and the shared release workflow: pushing a vX.Y.Z tag builds the
app, publishes <Name>-<version>-mac.zip on the GitHub Release and lists it in Shinjuku."
  if $dry_run; then
    echo "== Dry run: would open a PR on $repo with:"
    git show --stat --format='%s' HEAD | sed 's/^/   /'
    echo; cat "$workflow"
  else
    git push -q -u origin "$branch"
    pr_url=$(gh pr create -R "$repo" --head "$branch" --title "List in Shinjuku" --body "Adds \`shinjuku.json\` and the [shared release workflow](https://github.com/event-horizon-gg/shinjuku-release). Pushing a \`vX.Y.Z\` tag builds the app, publishes \`$name-<version>-mac.zip\` on the GitHub Release and lists it in Shinjuku. A tag like \`v1.0.0-beta.1\` becomes a beta.

Before merging:
- [ ] Fill in the TODOs in \`shinjuku.json\` (pitch, description, accent color, icon, screenshots)
- [ ] Check \`build-command\` and \`app-path\` in \`$workflow\`
- [ ] Make the build set \`CFBundleShortVersionString\` from \`\$SHINJUKU_VERSION\`")
  fi
fi

if $skip_secrets; then
  echo "Skipped secrets."
elif $dry_run; then
  echo "== Dry run: would set SHINJUKU_CATALOG_APP_ID ($app_id) and SHINJUKU_CATALOG_APP_KEY on $repo"
else
  gh secret set SHINJUKU_CATALOG_APP_ID -R "$repo" --body "$app_id"
  if [[ -n "$key_file" ]]; then
    gh secret set SHINJUKU_CATALOG_APP_KEY -R "$repo" < "$key_file"
  else
    op document get "$op_item" | gh secret set SHINJUKU_CATALOG_APP_KEY -R "$repo"
  fi
  # Stable signing identity, so macOS keeps Keychain approvals across updates.
  if $skip_signing; then
    echo "Skipped signing: releases will be ad-hoc signed."
  elif [[ -n "$signing_p12" ]]; then
    [[ -r "$signing_p12" ]] || die "can't read $signing_p12"
    read -r -s -p "Password for $signing_p12: " signing_password; echo
    base64 -i "$signing_p12" | gh secret set SHINJUKU_SIGNING_P12 -R "$repo"
    gh secret set SHINJUKU_SIGNING_PASSWORD -R "$repo" --body "$signing_password"
  elif command -v op >/dev/null && op document get "$signing_item" >/dev/null 2>&1; then
    op document get "$signing_item" | base64 | gh secret set SHINJUKU_SIGNING_P12 -R "$repo"
    op item get "$signing_item" --fields password --reveal | gh secret set SHINJUKU_SIGNING_PASSWORD -R "$repo"
  else
    echo "warning: no signing identity found (pass --signing-p12, or keep a 1Password document named"
    echo "         '$signing_item' with a password field). Releases will be ad-hoc signed until"
    echo "         SHINJUKU_SIGNING_P12 and SHINJUKU_SIGNING_PASSWORD are set on $repo."
  fi
fi

echo
echo "== Left for you"
[[ -n "$pr_url" ]] && echo "   PR: $pr_url"
grep -q TODO shinjuku.json 2>/dev/null && echo "   - Fill in the TODOs in shinjuku.json"
grep -q TODO "$workflow" 2>/dev/null && echo "   - Set build-command in $workflow"
echo "   - Make the build stamp the version from \$SHINJUKU_VERSION (the tag without the v)."
hits=$(git grep -n -I -e CFBundleShortVersionString -e MARKETING_VERSION -- ':!*.md' 2>/dev/null | head -5 || true)
if [[ -n "$hits" ]]; then
  echo "     The version is set here today:"
  cut -c1-140 <<<"$hits" | sed 's/^/       /'
fi
echo "   - Merge, then: git tag v1.0.0 && git push origin v1.0.0"
