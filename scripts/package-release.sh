#!/usr/bin/env bash
# Build, sign, archive, and generate Sparkle appcast.xml for a Saga macOS release.
#
# Usage:
#   ./scripts/package-release.sh [version] [build] [output-dir]
#
# Environment variables (optional in local/ad-hoc mode; used in CI):
#   SAGA_CODESIGN_P12_BASE64     — base64-encoded PKCS#12 code signing certificate
#   SAGA_CODESIGN_P12_PASSWORD   — password for the PKCS#12 file
#   SPARKLE_ED_PRIVATE_KEY_BASE64 — base64-encoded Sparkle EdDSA private key
#   SPARKLE_ED_KEY_FILE          — path to Sparkle EdDSA private key file
#   SAGA_RELEASE_NOTES           — release notes text for the appcast item
#   SAGA_REPO                    — GitHub repository (default: dgattey/saga)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/signing.sh
source "$ROOT/scripts/lib/signing.sh"

PBXPROJ="$ROOT/Saga/Saga.xcodeproj/project.pbxproj"
read_output="$("$ROOT/run" version-and-release read --path "$PBXPROJ")"
DEFAULT_VERSION="$(echo "$read_output" | awk -F= '/^VERSION=/{print $2}')"
DEFAULT_BUILD="$(echo "$read_output" | awk -F= '/^BUILD=/{print $2}')"

VERSION="${1:-$DEFAULT_VERSION}"
BUILD_NUMBER="${2:-$DEFAULT_BUILD}"
OUT_DIR="${3:-$ROOT/dist/release}"
REPO="${SAGA_REPO:-dgattey/saga}"

if [[ -z "$VERSION" || -z "$BUILD_NUMBER" ]]; then
  echo "package-release: version and build number are required" >&2
  exit 1
fi

decode_secret_b64() {
  printf '%s' "$1" | tr -d '[:space:]' | base64 -D 2>/dev/null || printf '%s' "$1" | tr -d '[:space:]' | base64 -d
}

cleanup_files=()
cleanup() {
  for f in "${cleanup_files[@]:-}"; do
    [[ -n "$f" && -e "$f" ]] && rm -rf "$f"
  done
}
trap cleanup EXIT

# 1. Optional CI P12 certificate import into an ephemeral build keychain
if [[ -n "${SAGA_CODESIGN_P12_BASE64:-}" && -n "${SAGA_CODESIGN_P12_PASSWORD:-}" ]]; then
  P12_PASS="$(printf '%s' "$SAGA_CODESIGN_P12_PASSWORD" | tr -d '[:space:]')"
  P12_FILE="$(mktemp /tmp/saga-codesign.XXXXXX.p12)"
  cleanup_files+=("$P12_FILE")
  decode_secret_b64 "$SAGA_CODESIGN_P12_BASE64" > "$P12_FILE"

  security delete-keychain saga-build.keychain 2>/dev/null || true
  security create-keychain -p "$P12_PASS" saga-build.keychain
  security set-keychain-settings -lut 21600 saga-build.keychain
  security default-keychain -s saga-build.keychain
  security unlock-keychain -p "$P12_PASS" saga-build.keychain
  security import "$P12_FILE" -k saga-build.keychain -f pkcs12 -P "$P12_PASS" -A \
    -T /usr/bin/codesign -T /usr/bin/security
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$P12_PASS" saga-build.keychain
  security list-keychains -d user -s saga-build.keychain login.keychain-db 2>/dev/null || security list-keychains -d user -s saga-build.keychain
fi

# 2. Optional CI Sparkle EdDSA private key decode
if [[ -z "${SPARKLE_ED_KEY_FILE:-}" && -n "${SPARKLE_ED_PRIVATE_KEY_BASE64:-}" ]]; then
  KEY_FILE="$(mktemp /tmp/saga-sparkle-ed.XXXXXX.key)"
  cleanup_files+=("$KEY_FILE")
  decode_secret_b64 "$SPARKLE_ED_PRIVATE_KEY_BASE64" > "$KEY_FILE"
  export SPARKLE_ED_KEY_FILE="$KEY_FILE"
fi

# 3. Ensure Config.xcconfig exists before building
"$ROOT/run" config --placeholder --if-missing

# 4. Build Release macOS app into a dedicated DerivedData path so we can deterministically locate Saga.app and Sparkle tools
DERIVED_DATA="$OUT_DIR/DerivedData"
STAGE_DIR="$OUT_DIR/stage"
rm -rf "$OUT_DIR"
mkdir -p "$STAGE_DIR"

ARCH="$(uname -m)"
echo "package-release: building Saga v${VERSION} (${BUILD_NUMBER}) for macOS (${ARCH})..."
xcodebuild \
  -quiet \
  -project "$ROOT/Saga/Saga.xcodeproj" \
  -scheme Saga \
  -configuration Release \
  -destination "platform=macOS,arch=${ARCH}" \
  -derivedDataPath "$DERIVED_DATA" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

BUILT_APP="$DERIVED_DATA/Build/Products/Release/Saga.app"
if [[ ! -d "$BUILT_APP" ]]; then
  echo "package-release: built app not found at $BUILT_APP" >&2
  exit 1
fi

APP="$STAGE_DIR/Saga.app"
ditto "$BUILT_APP" "$APP"

# 5. Sign embedded frameworks and Saga.app inside-out (never --deep, which corrupts Sparkle XPC services)
SIGN_ID="${SAGA_SIGN_IDENTITY:-$(resolve_sign_identity)}"
echo "package-release: signing Saga.app inside-out (identity=${SIGN_ID})..."

csign() {
  codesign --force --sign "$SIGN_ID" "$@"
}

if [[ -d "$APP/Contents/Frameworks" ]]; then
  for fw in "$APP/Contents/Frameworks"/*.framework; do
    [[ -d "$fw" ]] || continue
    if [[ "$(basename "$fw")" == "Sparkle.framework" ]]; then
      FWV="$fw/Versions/B"
      [[ -e "$FWV/XPCServices/Installer.xpc" ]] && csign "$FWV/XPCServices/Installer.xpc"
      if [[ -e "$FWV/XPCServices/Downloader.xpc" ]]; then
        codesign --force --sign "$SIGN_ID" --preserve-metadata=entitlements "$FWV/XPCServices/Downloader.xpc"
      fi
      [[ -e "$FWV/Autoupdate" ]] && csign "$FWV/Autoupdate"
      [[ -e "$FWV/Updater.app" ]] && csign "$FWV/Updater.app"
      csign "$fw"
    else
      csign "$fw"
    fi
  done

  for dylib in "$APP/Contents/Frameworks"/*.dylib; do
    [[ -f "$dylib" ]] || continue
    csign "$dylib"
  done
fi

ENTITLEMENTS="$ROOT/Saga/Saga/Config/Saga.entitlements"
if [[ -f "$ENTITLEMENTS" ]]; then
  csign --entitlements "$ENTITLEMENTS" "$APP"
else
  csign "$APP"
fi

codesign --verify --deep --strict "$APP"

# 6. Create Saga-<VERSION>.zip archive
ZIP_NAME="Saga-${VERSION}.zip"
ZIP_PATH="$OUT_DIR/$ZIP_NAME"
ditto -c -k --keepParent "$APP" "$ZIP_PATH"
rm -rf "$STAGE_DIR"

# 7. Generate appcast.xml (using Sparkle's generate_appcast when EdDSA key is available, or fallback XML)
DOWNLOAD_PREFIX="https://github.com/${REPO}/releases/download/v${VERSION}/"
DOWNLOAD_URL="${DOWNLOAD_PREFIX}${ZIP_NAME}"
RELEASE_LINK="https://github.com/${REPO}/releases/tag/v${VERSION}"
APPCAST_PATH="$OUT_DIR/appcast.xml"

GA="$(find_sparkle_tool generate_appcast "$DERIVED_DATA" || find_sparkle_tool generate_appcast || true)"
USED_GENERATE_APPCAST=false

if [[ -n "$GA" && -x "$GA" ]]; then
  GA_ARGS=(--download-url-prefix "$DOWNLOAD_PREFIX" --link "$RELEASE_LINK")
  if [[ -n "${SPARKLE_ED_KEY_FILE:-}" && -f "${SPARKLE_ED_KEY_FILE}" ]]; then
    GA_ARGS+=(--ed-key-file "$SPARKLE_ED_KEY_FILE")
  fi
  # Copy zip into an isolated directory for generate_appcast
  APPCAST_WORK="$(mktemp -d /tmp/saga-appcast.XXXXXX)"
  cleanup_files+=("$APPCAST_WORK")
  cp "$ZIP_PATH" "$APPCAST_WORK/$ZIP_NAME"
  if [[ -n "${SAGA_RELEASE_NOTES:-}" ]]; then
    printf '%s\n' "$SAGA_RELEASE_NOTES" > "$APPCAST_WORK/Saga-${VERSION}.txt"
  fi
  if "$GA" "${GA_ARGS[@]}" "$APPCAST_WORK" 2>/dev/null && [[ -f "$APPCAST_WORK/appcast.xml" ]]; then
    cp "$APPCAST_WORK/appcast.xml" "$APPCAST_PATH"
    USED_GENERATE_APPCAST=true
  fi
fi

if [[ "$USED_GENERATE_APPCAST" != true ]]; then
  echo "package-release: generating fallback appcast.xml (no Sparkle EdDSA private key in environment)" >&2
  ZIP_BYTES="$(wc -c <"$ZIP_PATH" | tr -d ' ')"
  PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
  NOTES_ESCAPED="$(printf '%s' "${SAGA_RELEASE_NOTES:-Release v${VERSION}}" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')"
  cat > "$APPCAST_PATH" <<XML
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <title>Saga</title>
    <link>${RELEASE_LINK}</link>
    <item>
      <title>${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <link>${RELEASE_LINK}</link>
      <sparkle:version>${BUILD_NUMBER}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <description>${NOTES_ESCAPED}</description>
      <enclosure url="${DOWNLOAD_URL}" length="${ZIP_BYTES}" type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML
fi

rm -rf "$DERIVED_DATA"

echo "package-release: packaged v${VERSION} (${BUILD_NUMBER})"
echo "  zip:     $ZIP_PATH"
echo "  appcast: $APPCAST_PATH"
