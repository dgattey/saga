#!/usr/bin/env bash
# Wait until a feed URL (default: the app's SAGA_FEED_URL) serves a well-formed appcast whose newest
# item has the same build number and EdDSA signature as an expected appcast. Follows redirects, as
# Sparkle does. PR CI points it at a local `next start`; release CI at the live site, before and
# after publishing.
#
# Usage: scripts/check-site-feed.sh <expected-appcast.xml> [feed-url] [timeout-seconds]   (default 900)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/app-config.sh
source "$ROOT/scripts/lib/app-config.sh"

EXPECTED="${1:?check-site-feed: expected appcast path is required (arg 1)}"
FEED="${2:-$SAGA_FEED_URL}"
TIMEOUT="${3:-900}"
LIVE="$(mktemp /tmp/saga-site-feed.XXXXXX)"
trap 'rm -f "$LIVE"' EXIT

build_of() { sed -n 's/.*<sparkle:version>\([^<]*\)<\/sparkle:version>.*/\1/p' "$1" | head -1; }
signature_of() { sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' "$1" | head -1; }
well_formed() { python3 -c 'import sys, xml.dom.minidom; xml.dom.minidom.parse(sys.argv[1])' "$1" 2>/dev/null; }

WANT_BUILD="$(build_of "$EXPECTED")"
WANT_SIGNATURE="$(signature_of "$EXPECTED")"
[[ -n "$WANT_BUILD" && -n "$WANT_SIGNATURE" ]] \
  || { echo "check-site-feed: $EXPECTED has no signed item" >&2; exit 1; }

deadline=$(($(date +%s) + TIMEOUT))
while :; do
  if curl -fsSL -H 'Cache-Control: no-cache' "$FEED?ts=$(date +%s)" -o "$LIVE" 2>/dev/null \
    && well_formed "$LIVE" \
    && [[ "$(build_of "$LIVE")" == "$WANT_BUILD" && "$(signature_of "$LIVE")" == "$WANT_SIGNATURE" ]]; then
    echo "check-site-feed: $FEED serves build $WANT_BUILD"
    exit 0
  fi
  if (($(date +%s) >= deadline)); then
    echo "check-site-feed: $FEED serves build '$(build_of "$LIVE" 2>/dev/null)', expected $WANT_BUILD" \
      "after ${TIMEOUT}s" >&2
    exit 1
  fi
  sleep 15
done
