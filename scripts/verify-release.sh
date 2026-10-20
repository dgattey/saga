#!/usr/bin/env bash
# Check that a packaged release is a valid Sparkle update for installs of the latest published
# release: same bundle ID, feed, and EdDSA key, a strictly higher build number, the same ad-hoc
# designated requirement and entitlements, and an appcast signature that verifies against the
# SUPublicEDKey baked into the published app.
#
# Usage:
#   ./scripts/verify-release.sh <new-zip> <new-appcast.xml>
#
# Environment variables:
#   SAGA_REPO — GitHub repository (default: dgattey/saga)
set -euo pipefail

NEW_ZIP="${1:?verify-release: zip path is required (arg 1)}"
NEW_APPCAST="${2:?verify-release: appcast path is required (arg 2)}"
REPO="${SAGA_REPO:-dgattey/saga}"

OPENSSL="openssl"
if [[ -x "$(brew --prefix openssl@3 2>/dev/null)/bin/openssl" ]]; then
  OPENSSL="$(brew --prefix openssl@3)/bin/openssl"
fi
"$OPENSSL" version | grep -q '^OpenSSL 3' || { echo "verify-release: OpenSSL 3 is required for Ed25519" >&2; exit 1; }

WORK="$(mktemp -d /tmp/saga-verify-release.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

curl -fsSL "https://github.com/${REPO}/releases/latest/download/appcast.xml" -o "$WORK/live-appcast.xml"
LIVE_URL="$(sed -n 's/.*<enclosure[^>]*url="\([^"]*\)".*/\1/p' "$WORK/live-appcast.xml" | head -1)"
curl -fsSL "$LIVE_URL" -o "$WORK/live.zip"
mkdir -p "$WORK/live" "$WORK/new"
ditto -x -k "$WORK/live.zip" "$WORK/live"
ditto -x -k "$NEW_ZIP" "$WORK/new"
LIVE_APP="$WORK/live/Saga.app"
NEW_APP="$WORK/new/Saga.app"

plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null || true; }
appcast_value() { sed -n "s/.*<sparkle:$2>\([^<]*\)<\/sparkle:$2>.*/\1/p" "$1" | head -1; }

failures=0
check() {
  local label="$1" ok="$2" detail="$3"
  if [[ "$ok" == 1 ]]; then
    echo "  ok    $label ($detail)"
  else
    echo "  FAIL  $label ($detail)"
    failures=$((failures + 1))
  fi
}
same() { [[ "$1" == "$2" ]] && echo 1 || echo 0; }

echo "verify-release: comparing $(basename "$NEW_ZIP") against live $(basename "$LIVE_URL")"

for key in CFBundleIdentifier CFBundleExecutable SUFeedURL SUPublicEDKey LSMinimumSystemVersion; do
  live="$(plist "$LIVE_APP" "$key")"
  new="$(plist "$NEW_APP" "$key")"
  check "Info.plist $key" "$(same "$live" "$new")" "live=$live new=$new"
done

LIVE_BUILD="$(appcast_value "$WORK/live-appcast.xml" version)"
NEW_BUILD="$(plist "$NEW_APP" CFBundleVersion)"
check "build number increases" "$([[ "$NEW_BUILD" -gt "$LIVE_BUILD" ]] && echo 1 || echo 0)" "live=$LIVE_BUILD new=$NEW_BUILD"
check "appcast sparkle:version matches app" \
  "$(same "$(appcast_value "$NEW_APPCAST" version)" "$NEW_BUILD")" "appcast=$(appcast_value "$NEW_APPCAST" version)"
check "appcast shortVersionString matches app" \
  "$(same "$(appcast_value "$NEW_APPCAST" shortVersionString)" "$(plist "$NEW_APP" CFBundleShortVersionString)")" \
  "appcast=$(appcast_value "$NEW_APPCAST" shortVersionString)"

codesign --verify --deep --strict "$NEW_APP" && verified=1 || verified=0
check "codesign --verify --deep --strict" "$verified" "new app"
LIVE_REQ="$(codesign -d -r- "$LIVE_APP" 2>/dev/null | sed -n 's/^designated => //p')"
NEW_REQ="$(codesign -d -r- "$NEW_APP" 2>/dev/null | sed -n 's/^designated => //p')"
check "designated requirement" "$(same "$LIVE_REQ" "$NEW_REQ")" "$NEW_REQ"
LIVE_ENT="$(codesign -d --entitlements - --xml "$LIVE_APP" 2>/dev/null | plutil -convert json -o - - 2>/dev/null || true)"
NEW_ENT="$(codesign -d --entitlements - --xml "$NEW_APP" 2>/dev/null | plutil -convert json -o - - 2>/dev/null || true)"
check "entitlements" "$(same "$LIVE_ENT" "$NEW_ENT")" "$NEW_ENT"
LIVE_SIGNER="$(codesign -dvv "$LIVE_APP" 2>&1 | sed -n 's/^Signature=//p')"
NEW_SIGNER="$(codesign -dvv "$NEW_APP" 2>&1 | sed -n 's/^Signature=//p')"
check "signing scheme" "$(same "$LIVE_SIGNER" "$NEW_SIGNER")" "Signature=$NEW_SIGNER"

# Existing installs verify updates with the SUPublicEDKey in the *published* app's Info.plist.
LIVE_KEY="$(plist "$LIVE_APP" SUPublicEDKey)"
ED_SIG="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' "$NEW_APPCAST" | head -1)"
{
  echo "-----BEGIN PUBLIC KEY-----"
  printf '302a300506032b6570032100%s' "$(printf '%s' "$LIVE_KEY" | base64 -D | xxd -p -c 64)" | xxd -r -p | base64
  echo "-----END PUBLIC KEY-----"
} >"$WORK/live-pub.pem"
printf '%s' "$ED_SIG" | base64 -D >"$WORK/new.sig"
"$OPENSSL" pkeyutl -verify -pubin -inkey "$WORK/live-pub.pem" -rawin -in "$NEW_ZIP" -sigfile "$WORK/new.sig" >/dev/null 2>&1 \
  && sig_ok=1 || sig_ok=0
check "sparkle:edSignature verifies against live SUPublicEDKey" "$sig_ok" "key=$LIVE_KEY"
NEW_LENGTH="$(sed -n 's/.*<enclosure[^>]*length="\([0-9]*\)".*/\1/p' "$NEW_APPCAST" | head -1)"
check "enclosure length matches zip" "$(same "$NEW_LENGTH" "$(wc -c <"$NEW_ZIP" | tr -d ' ')")" "length=$NEW_LENGTH"

# Credentials are summarized by length so real values never reach CI logs.
plist_summary() {
  plutil -convert json -o - "$1/Contents/Info.plist" | python3 -c '
import json, sys
d = json.load(sys.stdin)
for k in sorted(d):
    if k.startswith(("DT", "BuildMachine")):
        continue
    v = f"<{len(d[k])} chars>" if k.startswith(("Contentful", "SagaAPISecret")) else d[k]
    print(f"{k} = {v}")'
}
echo
echo "Info.plist (live → new), ignoring Xcode DT*/BuildMachine metadata:"
diff <(plist_summary "$LIVE_APP") <(plist_summary "$NEW_APP") || true

if [[ "$failures" -gt 0 ]]; then
  echo "verify-release: $failures check(s) failed" >&2
  exit 1
fi
echo "verify-release: all checks passed"
