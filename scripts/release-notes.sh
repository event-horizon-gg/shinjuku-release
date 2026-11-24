#!/usr/bin/env bash
# Prints the release notes for a tag, as Markdown: a real changelog, never just a compare link.
#
#   scripts/release-notes.sh v1.4.0 [repo-dir]
#
# 1. If CHANGELOG.md has a section for the version ("## 1.4.0", "## [1.4.0]", "## v1.4.0 – date"),
#    that section is the notes.
# 2. Otherwise: the commit subjects since the previous tag, minus merges and housekeeping.
# Needs the repo's full history and tags (actions/checkout with fetch-depth: 0).
set -euo pipefail
tag="$1"
dir="${2:-.}"
cd "$dir"
version="${tag#v}"

if [[ -f CHANGELOG.md ]]; then
  section=$(awk -v v="$version" '
    BEGIN { found = 0 }
    /^## / {
      if (found) exit
      line = $0
      gsub(/[\[\]v]/, "", line)
      split(line, parts, /[ \t]+/)
      if (parts[2] == v) { found = 1; next }
    }
    found { print }
  ' CHANGELOG.md | sed -e '/./,$!d')
  if [[ -n "${section//[[:space:]]/}" ]]; then
    printf '%s\n' "$section"
    exit 0
  fi
fi

previous=$(git describe --tags --abbrev=0 --match 'v[0-9]*' "${tag}^" 2>/dev/null || true)
range="${previous:+$previous..}$tag"
changes=$(git log "$range" --no-merges --format='%s' \
  | grep -viE '^(merge |bump version|release [0-9v]|ci experiment|wip\b|fixup!|squash!)' \
  | awk '!seen[$0]++' \
  | sed 's/^/- /' || true)

echo "## Changes"
echo
if [[ -n "$changes" ]]; then
  limit=25
  count=$(printf '%s\n' "$changes" | wc -l | tr -d ' ')
  printf '%s\n' "$changes" | head -n "$limit"
  if (( count > limit )); then echo "- …and $((count - limit)) earlier changes."; fi
elif [[ -n "$previous" ]]; then
  echo "- Rebuilt from the same code as $previous."
else
  echo "- First release."
fi
