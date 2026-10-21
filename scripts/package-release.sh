#!/usr/bin/env bash
# Build, sign, archive, and generate Sparkle appcast.xml for a Saga macOS release.
#
# Uses ad-hoc code signing (`-`) with `com.apple.security.cs.disable-library-validation`
# (`Saga.entitlements`) + Sparkle 2 EdDSA (`SUPublicEDKey` in `Info.plist` and
# `sparkle:edSignature` in `appcast.xml`). Untrusted self-signed X.509 certificates are
# rejected by Gatekeeper / `syspolicyd` / `amfid` on macOS Sequoia/Tahoe when quarantined,
# whereas ad-hoc (`-`) works cleanly with **Privacy & Security → Open Anyway** and Sparkle 2.
#
# Usage:
#   ./scripts/package-release.sh <version> <build> [output-dir]
#
# Environment variables (optional in local/ad-hoc mode; used in CI):
#   SPARKLE_ED_PRIVATE_KEY_BASE64 — base64-encoded Sparkle EdDSA private key
#   SPARKLE_ED_KEY_FILE          — path to Sparkle EdDSA private key file
#   SAGA_SIGN_IDENTITY           — code signing identity override (default: ad-hoc `-`)
#   SAGA_RELEASE_NOTES           — release notes text for the appcast item
#   SAGA_REPO                    — GitHub repository (default: dgattey/saga)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

VERSION="${1:?package-release: version is required (arg 1)}"
BUILD_NUMBER="${2:?package-release: build number is required (arg 2)}"
OUT_DIR="${3:-$ROOT/dist/release}"
STAGE_DIR="$OUT_DIR/stage"
rm -rf "$OUT_DIR"
mkdir -p "$STAGE_DIR"

echo "package-release: building Saga v${VERSION} (${BUILD_NUMBER}) for macOS ($(uname -m))..."
SAGA_DIST_DIR="$STAGE_DIR" \
SAGA_APP_SHORT_VERSION="$VERSION" \
SAGA_BUILD_NUMBER="$BUILD_NUMBER" \
  "$ROOT/scripts/build-macos.sh" release >/dev/null
APP="$STAGE_DIR/Saga.app"

ZIP_PATH="$OUT_DIR/Saga-${VERSION}.zip"
ditto -c -k --keepParent "$APP" "$ZIP_PATH"
rm -rf "$STAGE_DIR"

REQUIRE_SPARKLE_SIGNATURE="${REQUIRE_SPARKLE_SIGNATURE:-1}" \
  "$ROOT/scripts/generate-appcast.sh" "$VERSION" "$BUILD_NUMBER" "$ZIP_PATH" "$OUT_DIR/appcast.xml"

echo "package-release: packaged v${VERSION} (${BUILD_NUMBER})"
echo "  zip:     $ZIP_PATH"
echo "  appcast: $OUT_DIR/appcast.xml"
