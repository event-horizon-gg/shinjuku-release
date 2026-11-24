#!/usr/bin/env bash
# Creates the "Event Horizon Releases" code-signing identity and stores it as secrets on app repos.
#
#   scripts/make-signing-identity.sh event-horizon-gg/shinjuku [event-horizon-gg/other-app ...]
#
# Why: ad-hoc signatures change on every build, so macOS treats each update as a new app and
# asks again for Keychain items it already allowed. Signing every release with one fixed
# certificate keeps the app's identity stable, so "Always Allow" sticks across updates.
# It is self-signed: it doesn't notarize anything and Gatekeeper still asks on first open.
#
# Writes ~/event-horizon-releases.p12 and prints its password once. Save both in 1Password:
# re-running this makes a NEW identity, and every app signed with it will ask once more.
# To add the same identity to another repo later:
#   scripts/make-signing-identity.sh --reuse ~/event-horizon-releases.p12 event-horizon-gg/new-app
set -euo pipefail

name="Event Horizon Releases"
p12="$HOME/event-horizon-releases.p12"
reuse=false
if [[ "${1:-}" == "--reuse" ]]; then reuse=true; p12="$2"; shift 2; fi
[[ $# -ge 1 ]] || { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
command -v openssl >/dev/null || { echo "needs openssl" >&2; exit 1; }

if $reuse; then
  [[ -r "$p12" ]] || { echo "can't read $p12" >&2; exit 1; }
  read -r -s -p "Password for $p12: " password; echo
else
  [[ ! -e "$p12" ]] || { echo "$p12 already exists; use --reuse, or move it away to make a new identity" >&2; exit 1; }
  work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
  password="$(openssl rand -base64 24)"
  cat > "$work/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $name
O = event-horizon-gg
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
  openssl req -x509 -newkey rsa:3072 -nodes -days 3650 -config "$work/cert.cnf" \
    -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
  # OpenSSL 3 needs -legacy for a .p12 macOS's security tool can read; LibreSSL
  # (macOS's built-in openssl) writes that format already and has no such flag.
  legacy=()
  openssl pkcs12 -help 2>&1 | grep -q -- '-legacy' && legacy=(-legacy)
  openssl pkcs12 -export "${legacy[@]}" -inkey "$work/key.pem" -in "$work/cert.pem" -name "$name" \
    -out "$p12" -passout "pass:$password"
  chmod 600 "$p12"
fi

for repo in "$@"; do
  base64 -i "$p12" | gh secret set SHINJUKU_SIGNING_P12 -R "$repo"
  gh secret set SHINJUKU_SIGNING_PASSWORD -R "$repo" --body "$password"
done

echo
echo "Signing identity: $name"
echo "Saved to: $p12"
if ! $reuse; then
  echo "Password (shown once): $password"
  echo "Store the .p12 file and this password in 1Password, then delete $p12."
fi
