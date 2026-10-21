#!/usr/bin/env bash
# Build build/Saga.app from the SwiftPM `Saga` product: compiles the Core Data model and asset
# catalogs, embeds Sparkle.framework, writes Info.plist, and signs inside-out.
#
# Usage:
#   scripts/build-macos.sh [debug|release]
#
# Environment variables (all optional):
#   SAGA_APP_SHORT_VERSION  — CFBundleShortVersionString (default: VERSION)
#   SAGA_BUILD_NUMBER       — CFBundleVersion (default: half-hours since repo inception, like releases)
#   SAGA_SIGN_IDENTITY      — codesign identity (default: ad-hoc `-`)
#   SAGA_DIST_DIR           — output directory for Saga.app (default: build/)
#   CONTENTFUL_SPACE_ID / CONTENTFUL_ACCESS_TOKEN / SAGA_API_SECRET — override Config.xcconfig
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=scripts/lib/signing.sh
source "$ROOT/scripts/lib/signing.sh"
# shellcheck source=scripts/lib/app-config.sh
source "$ROOT/scripts/lib/app-config.sh"

CONFIG="${1:-debug}"
case "$CONFIG" in
  debug|release) ;;
  *)
    echo "Usage: scripts/build-macos.sh [debug|release]" >&2
    exit 2
    ;;
esac

# Keep in sync with Constants.repoInception in scripts/Sources/version-and-release/main.swift.
REPO_INCEPTION=1751838521
SHORT_VERSION="${SAGA_APP_SHORT_VERSION:-$(tr -d '[:space:]' <"$ROOT/VERSION")}"
BUILD_NUMBER="${SAGA_BUILD_NUMBER:-$(( ($(date +%s) - REPO_INCEPTION) / 1800 ))}"
SIGN_ID="$(resolve_sign_identity)"
SU_FEED_URL="$SAGA_FEED_URL"
SU_PUBLIC_KEY="$(tr -d '[:space:]' <"$ROOT/sparkle-public-key.txt")"

swift build -c "$CONFIG" --product Saga
BIN_DIR="$(swift build -c "$CONFIG" --product Saga --show-bin-path)"
BINARY="$BIN_DIR/Saga"
SPARKLE_SRC="$BIN_DIR/Sparkle.framework"
[[ -f "$BINARY" ]] || { echo "build-macos: $BINARY missing" >&2; exit 1; }
[[ -d "$SPARKLE_SRC" ]] || { echo "build-macos: $SPARKLE_SRC missing" >&2; exit 1; }

DIST="${SAGA_DIST_DIR:-$ROOT/build}"
APP="$DIST/Saga.app"
CONTENTS="$APP/Contents"
RESOURCES_DIR="$CONTENTS/Resources"
FRAMEWORKS_DIR="$CONTENTS/Frameworks"
PLIST_FILE="$CONTENTS/Info.plist"
WORK_DIR="$(mktemp -d /tmp/saga-build-macos.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"
cp "$BINARY" "$CONTENTS/MacOS/Saga"

# Strip absolute build-machine / Xcode toolchain LC_RPATH entries that SwiftPM embeds
# (e.g. /Applications/Xcode_26.5.app/.../usr/lib/swift-6.2/macosx on CI runners), keeping only
# bundle-relative or /usr/lib/swift paths so XprotectService never logs an rPathCmd failure.
while IFS= read -r rpath; do
  case "$rpath" in
    ""|@executable_path*|@loader_path*|/usr/lib/swift*) ;;
    *) install_name_tool -delete_rpath "$rpath" "$CONTENTS/MacOS/Saga" ;;
  esac
done < <(otool -l "$CONTENTS/MacOS/Saga" | awk '/cmd LC_RPATH/{f=1;next} f && /path /{print $2; f=0}')

# ditto preserves the framework symlinks codesign needs.
ditto "$SPARKLE_SRC" "$FRAMEWORKS_DIR/Sparkle.framework"

xcrun momc --macosx-deployment-target "$SAGA_MIN_OS" "$SAGA_SOURCES/Saga.xcdatamodeld" "$RESOURCES_DIR/"

# Compiles Assets.car (accent colors + Liquid Glass icon) and the AppIcon.icns fallback.
xcrun actool "$SAGA_SOURCES/Assets.xcassets" "$SAGA_SOURCES/AppIcon.icon" \
  --compile "$RESOURCES_DIR" \
  --platform macosx \
  --minimum-deployment-target "$SAGA_MIN_OS" \
  --app-icon AppIcon \
  --accent-color AccentColor \
  --output-partial-info-plist "$WORK_DIR/assetcatalog_generated_info.plist" \
  --errors --warnings >/dev/null

printf 'APPL????' > "$CONTENTS/PkgInfo"
cat > "$PLIST_FILE" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>Saga</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>${SAGA_BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Saga</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${SHORT_VERSION}</string>
  <key>CFBundleSupportedPlatforms</key>
  <array>
    <string>MacOSX</string>
  </array>
  <key>CFBundleVersion</key>
  <string>${BUILD_NUMBER}</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key>
  <string>${SAGA_MIN_OS}</string>
  <key>NSAccentColorName</key>
  <string>AccentColor</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUFeedURL</key>
  <string>${SU_FEED_URL}</string>
  <key>SUPublicEDKey</key>
  <string>${SU_PUBLIC_KEY}</string>
  <key>SUScheduledCheckInterval</key>
  <integer>3600</integer>
</dict>
</plist>
PLIST
saga_insert_credentials "$PLIST_FILE"
plutil -lint "$PLIST_FILE" >/dev/null

# Strip quarantine / provenance extended attributes so nothing stale gets sealed or packaged.
xattr -cr "$APP" 2>/dev/null || true

csign() {
  codesign --force --sign "$SIGN_ID" "$@"
}

# Sign Sparkle inside-out (XPC services, helper, Updater.app, then the framework). Never --deep:
# it corrupts the XPC signatures. Order matters so the outer signature seals valid inner ones.
FWV="$FRAMEWORKS_DIR/Sparkle.framework/Versions/B"
csign "$FWV/XPCServices/Installer.xpc"
# Downloader.xpc ships sandbox/network entitlements that must survive re-signing.
csign --preserve-metadata=entitlements "$FWV/XPCServices/Downloader.xpc"
csign "$FWV/Autoupdate"
csign "$FWV/Updater.app"
csign "$FRAMEWORKS_DIR/Sparkle.framework"

# When ad-hoc signing, pin the designated requirement to the bundle identifier rather than the
# default cdhash so Sparkle's SUCodeSigningVerifier matches old and new builds.
if [[ "$SIGN_ID" == "-" ]]; then
  csign --entitlements "$ROOT/Saga.entitlements" -r="designated => identifier \"${SAGA_BUNDLE_ID}\"" "$APP"
else
  csign --entitlements "$ROOT/Saga.entitlements" "$APP"
fi
codesign --verify --deep --strict "$APP"

echo "build-macos: $APP (${SHORT_VERSION} build ${BUILD_NUMBER}, identity ${SIGN_ID})" >&2
echo "$APP"
