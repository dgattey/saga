#!/usr/bin/env bash
# Build, sign, archive, and generate Sparkle appcast.xml for a Saga macOS release.
#
# Uses ad-hoc code signing (`-`) with `com.apple.security.cs.disable-library-validation`
# (`Saga/Saga/Config/Saga.entitlements`) + Sparkle 2 EdDSA (`SUPublicEDKey` in `Info.plist`
# and `sparkle:edSignature` in `appcast.xml`). Untrusted self-signed X.509 certificates are
# rejected by Gatekeeper / `syspolicyd` / `amfid` on macOS Sequoia/Tahoe when quarantined,
# whereas ad-hoc (`-`) works cleanly with **Privacy & Security → Open Anyway** and Sparkle 2.
#
# Usage:
#   ./scripts/package-release.sh [version] [build] [output-dir]
#
# Environment variables (optional in local/ad-hoc mode; used in CI):
#   SPARKLE_ED_PRIVATE_KEY_BASE64 — base64-encoded Sparkle EdDSA private key
#   SPARKLE_ED_KEY_FILE          — path to Sparkle EdDSA private key file
#   SAGA_SIGN_IDENTITY           — code signing identity override (default: ad-hoc `-`)
#   SAGA_SIGN_ENTITLEMENTS       — entitlements plist override (default: Saga/Saga/Config/Saga.entitlements)
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

# 1. Optional CI Sparkle EdDSA private key decode
if [[ -z "${SPARKLE_ED_KEY_FILE:-}" && -n "${SPARKLE_ED_PRIVATE_KEY_BASE64:-}" ]]; then
  KEY_FILE="$(mktemp /tmp/saga-sparkle-ed.XXXXXX.key)"
  cleanup_files+=("$KEY_FILE")
  decode_secret_b64 "$SPARKLE_ED_PRIVATE_KEY_BASE64" > "$KEY_FILE"
  export SPARKLE_ED_KEY_FILE="$KEY_FILE"
fi

# 2. Ensure Config.xcconfig exists before building
"$ROOT/run" config --placeholder --if-missing

# 3. Build Release macOS app into a dedicated DerivedData path so we can deterministically locate Saga.app and Sparkle tools
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
  ENABLE_APP_SANDBOX=NO \
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

# 3b. Strip any absolute build-machine / Xcode toolchain LC_RPATH entries (e.g.
# /Applications/Xcode_26.5.app/.../usr/lib/swift-6.2/macosx on CI runners), keeping only
# bundle-relative (@executable_path / @loader_path) or /usr/lib/swift paths so XprotectService
# never logs an rPathCmd lookup failure during Gatekeeper assessment.
strip_non_portable_rpaths() {
  local bin="$1"
  [[ -f "$bin" ]] || return 0
  while IFS= read -r rpath; do
    [[ -z "$rpath" ]] && continue
    case "$rpath" in
      @executable_path*|@loader_path*|/usr/lib/swift*) ;;
      *)
        install_name_tool -delete_rpath "$rpath" "$bin" 2>/dev/null || true
        ;;
    esac
  done < <(otool -l "$bin" 2>/dev/null | awk '/cmd LC_RPATH/{f=1;next} f && /path /{print $2; f=0}')
}

APP_BIN="$APP/Contents/MacOS/Saga"
strip_non_portable_rpaths "$APP_BIN"
if [[ -f "$APP_BIN" ]] && ! otool -l "$APP_BIN" | awk '/cmd LC_RPATH/{f=1;next} f && /path /{print $2; f=0}' | grep -Fxq '@executable_path/../Frameworks'; then
  install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP_BIN" 2>/dev/null || true
fi

if [[ -d "$APP/Contents/Frameworks" ]]; then
  for fw in "$APP/Contents/Frameworks"/*.framework; do
    [[ -d "$fw" ]] || continue
    fw_name="$(basename "$fw" .framework)"
    if [[ -f "$fw/Versions/Current/$fw_name" ]]; then
      strip_non_portable_rpaths "$fw/Versions/Current/$fw_name"
    elif [[ -f "$fw/$fw_name" ]]; then
      strip_non_portable_rpaths "$fw/$fw_name"
    fi
  done
  for dylib in "$APP/Contents/Frameworks"/*.dylib; do
    [[ -f "$dylib" ]] || continue
    strip_non_portable_rpaths "$dylib"
  done
fi

# Strip any quarantine / provenance extended attributes before signing so nothing stale
# or inherited from artifact downloads gets sealed or packaged.
xattr -cr "$APP" 2>/dev/null || true

# 4. Sign embedded frameworks and Saga.app inside-out (never --deep, which corrupts Sparkle XPC services)
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

ENTITLEMENTS="${SAGA_SIGN_ENTITLEMENTS:-$ROOT/Saga/Saga/Config/Saga.entitlements}"
if [[ ! -f "$ENTITLEMENTS" ]]; then
  echo "package-release: entitlements file not found at $ENTITLEMENTS" >&2
  exit 1
fi
csign --entitlements "$ENTITLEMENTS" "$APP"

codesign --verify --deep --strict "$APP"

# 5. Create Saga-<VERSION>.zip archive
ZIP_NAME="Saga-${VERSION}.zip"
ZIP_PATH="$OUT_DIR/$ZIP_NAME"
ditto -c -k --keepParent "$APP" "$ZIP_PATH"
rm -rf "$STAGE_DIR"

# 6. Generate appcast.xml (using Sparkle's generate_appcast when EdDSA key is available, or fallback XML)
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
