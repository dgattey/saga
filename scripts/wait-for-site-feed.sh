#!/usr/bin/env bash
# Wait until the site (SAGA_FEED_URL) serves server/public/appcast.xml: a well-formed feed whose
# newest item has the committed build number and EdDSA signature. Release CI runs this before
# publishing, so installs that poll the site never see a missing or stale feed.
#
# Usage: scripts/wait-for-site-feed.sh [timeout-seconds]   (default 900)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/app-config.sh
source "$ROOT/scripts/lib/app-config.sh"

TIMEOUT="${1:-900}"
COMMITTED="$ROOT/server/public/appcast.xml"
LIVE="$(mktemp /tmp/saga-site-feed.XXXXXX)"
trap 'rm -f "$LIVE"' EXIT

build_of() { sed -n 's/.*<sparkle:version>\([^<]*\)<\/sparkle:version>.*/\1/p' "$1" | head -1; }
signature_of() { sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' "$1" | head -1; }

WANT_BUILD="$(build_of "$COMMITTED")"
WANT_SIGNATURE="$(signature_of "$COMMITTED")"
[[ -n "$WANT_BUILD" && -n "$WANT_SIGNATURE" ]] \
  || { echo "wait-for-site-feed: $COMMITTED has no signed item" >&2; exit 1; }

deadline=$(($(date +%s) + TIMEOUT))
while :; do
  if curl -fsSL -H 'Cache-Control: no-cache' "$SAGA_FEED_URL?ts=$(date +%s)" -o "$LIVE" 2>/dev/null \
    && xmllint --noout "$LIVE" 2>/dev/null \
    && [[ "$(build_of "$LIVE")" == "$WANT_BUILD" && "$(signature_of "$LIVE")" == "$WANT_SIGNATURE" ]]; then
    echo "wait-for-site-feed: $SAGA_FEED_URL serves build $WANT_BUILD"
    exit 0
  fi
  if (($(date +%s) >= deadline)); then
    echo "wait-for-site-feed: $SAGA_FEED_URL still serves build '$(build_of "$LIVE" 2>/dev/null)'," \
      "expected $WANT_BUILD after ${TIMEOUT}s" >&2
    exit 1
  fi
  sleep 15
done
