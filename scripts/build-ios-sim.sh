#!/usr/bin/env bash
# Build build/Saga-iOS.app for the iOS Simulator from the SwiftPM `Saga` product.
#
# Usage:
#   scripts/build-ios-sim.sh [--install]   # --install also installs into the booted simulator
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=scripts/lib/app-config.sh
source "$ROOT/scripts/lib/app-config.sh"

SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
TRIPLE="$(uname -m)-apple-ios${SAGA_MIN_OS}-simulator"
SCRATCH="$ROOT/.build/ios-sim"
APP="$ROOT/build/Saga-iOS.app"
WORK_DIR="$(mktemp -d /tmp/saga-build-ios-sim.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT

SWIFT_BUILD=(swift build --product Saga --triple "$TRIPLE" --sdk "$SDK_PATH" --scratch-path "$SCRATCH")
"${SWIFT_BUILD[@]}"
BIN_DIR="$("${SWIFT_BUILD[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP"
cp "$BIN_DIR/Saga" "$APP/Saga"

xcrun momc --iphonesimulator-deployment-target "$SAGA_MIN_OS" "$SAGA_SOURCES/Saga.xcdatamodeld" "$APP/"

PARTIAL_PLIST="$WORK_DIR/assetcatalog_generated_info.plist"
xcrun actool "$SAGA_SOURCES/Assets.xcassets" "$SAGA_SOURCES/AppIcon.icon" \
  --compile "$APP" \
  --platform iphonesimulator \
  --target-device iphone \
  --target-device ipad \
  --minimum-deployment-target "$SAGA_MIN_OS" \
  --app-icon AppIcon \
  --accent-color AccentColor \
  --output-partial-info-plist "$PARTIAL_PLIST" \
  --errors --warnings >/dev/null

cat > "$APP/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>Saga</string>
  <key>CFBundleIdentifier</key>
  <string>${SAGA_BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Saga</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$(tr -d '[:space:]' <"$ROOT/VERSION")</string>
  <key>CFBundleSupportedPlatforms</key>
  <array>
    <string>iPhoneSimulator</string>
  </array>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSRequiresIPhoneOS</key>
  <true/>
  <key>MinimumOSVersion</key>
  <string>${SAGA_MIN_OS}</string>
  <key>UIApplicationSceneManifest</key>
  <dict>
    <key>UIApplicationSupportsMultipleScenes</key>
    <true/>
  </dict>
  <key>UIApplicationSupportsIndirectInputEvents</key>
  <true/>
  <key>UIDeviceFamily</key>
  <array>
    <integer>1</integer>
    <integer>2</integer>
  </array>
  <key>UILaunchScreen</key>
  <dict/>
  <key>UIStatusBarStyle</key>
  <string>UIStatusBarStyleDefault</string>
  <key>UISupportedInterfaceOrientations~iphone</key>
  <array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
  </array>
  <key>UISupportedInterfaceOrientations~ipad</key>
  <array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationPortraitUpsideDown</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
  </array>
</dict>
</plist>
PLIST
# actool's partial plist carries the CFBundleIcons / NSAccentColorName entries it compiled.
/usr/libexec/PlistBuddy -c "Merge $PARTIAL_PLIST" "$APP/Info.plist" >/dev/null
saga_insert_credentials "$APP/Info.plist"
plutil -lint "$APP/Info.plist" >/dev/null

codesign --force --sign - "$APP"

if [[ "${1:-}" == "--install" ]]; then
  xcrun simctl install booted "$APP"
fi

echo "$APP"
