#!/usr/bin/env bash
# Headless iOS Simulator screenshots of Saga's main screens, checked against what each launch asked for.
#
# Builds build/Saga-iOS.app, seeds a fixture store (scripts/ui-fixture-store.swift) into a fresh iPhone
# and iPad simulator, launches with --initial-view home|book in light and dark, and writes PNGs to
# build/captures/. Fails if the app crashes, doesn't log the screen and book count it was asked for,
# loses the seeded books, or renders two different screens identically. Simulator.app never opens and
# the simulators it creates are deleted afterwards.
#
# Usage: scripts/ui-screenshots.sh [--no-build]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=scripts/lib/app-config.sh
source "$ROOT/scripts/lib/app-config.sh"

APP="$ROOT/build/Saga-iOS.app"
CAPTURES="$ROOT/build/captures"
SETTLE="${SAGA_UI_SETTLE:-8}"
WORK_DIR="$(mktemp -d /tmp/saga-ui-screenshots.XXXXXX)"
DEVICES=()

cleanup() {
  for udid in "${DEVICES[@]+"${DEVICES[@]}"}"; do
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    xcrun simctl delete "$udid" >/dev/null 2>&1 || true
  done
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

fail() {
  echo "ui-screenshots: FAIL $*" >&2
  exit 1
}

# Prints "<device type id> <runtime id>" for the newest iOS runtime with an available device whose name
# matches the regex in $1.
device_type_and_runtime() {
  xcrun simctl list -j devices available | python3 -c '
import json, re, sys
pattern = re.compile(sys.argv[1])
devices = json.load(sys.stdin)["devices"]
def version(runtime):
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    return (int(match[1]), int(match[2])) if match else (0, 0)
for runtime in sorted((r for r in devices if "SimRuntime.iOS" in r), key=version, reverse=True):
    for device in devices[runtime]:
        if pattern.search(device["name"]):
            print(device["deviceTypeIdentifier"], runtime)
            sys.exit(0)
sys.exit(1)
' "$1"
}

if [[ "${1:-}" != "--no-build" ]]; then
  "$ROOT/scripts/build-ios-sim.sh" >/dev/null
fi
[[ -d "$APP" ]] || fail "$APP is missing; run scripts/build-ios-sim.sh"

FIXTURE="$WORK_DIR/Saga.sqlite"
xcrun swift "$ROOT/scripts/ui-fixture-store.swift" "$APP/Saga.momd" "$FIXTURE"
BOOK_COUNT="$(sqlite3 "$FIXTURE" 'SELECT COUNT(*) FROM ZBOOK')"
READING_TITLE="$(sqlite3 "$FIXTURE" 'SELECT ZTITLE FROM ZBOOK WHERE ZREADDATEFINISHED IS NULL LIMIT 1')"

rm -rf "$CAPTURES"
mkdir -p "$CAPTURES"

capture_device() {
  local label="$1" name_pattern="$2" type runtime udid container
  read -r type runtime < <(device_type_and_runtime "$name_pattern") \
    || fail "no available simulator matching '$name_pattern'"
  udid="$(xcrun simctl create "Saga UI $label" "$type" "$runtime")"
  DEVICES+=("$udid")
  echo "ui-screenshots: $label on ${type##*.} / ${runtime##*.} ($udid)"

  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 \
    >/dev/null 2>&1 || true
  xcrun simctl install "$udid" "$APP"
  container="$(xcrun simctl get_app_container "$udid" "$SAGA_BUNDLE_ID" data)"
  mkdir -p "$container/Library/Application Support"
  cp "$FIXTURE" "$container/Library/Application Support/Saga.sqlite"

  local view appearance started logs output
  for view in home book; do
    for appearance in light dark; do
      started="$(date '+%Y-%m-%d %H:%M:%S')"
      SIMCTL_CHILD_SAGA_INITIAL_VIEW="$view" SIMCTL_CHILD_SAGA_APPEARANCE="$appearance" \
        xcrun simctl launch --terminate-running-process "$udid" "$SAGA_BUNDLE_ID" >/dev/null
      sleep "$SETTLE"

      grep -qF "UIKitApplication:$SAGA_BUNDLE_ID" <<<"$(xcrun simctl spawn "$udid" launchctl list)" \
        || fail "$label $view $appearance: Saga isn't running after ${SETTLE}s (crashed?)"
      output="$CAPTURES/saga-$label-$view-$appearance.png"
      xcrun simctl io "$udid" screenshot --type=png "$output" >/dev/null 2>&1
      [[ -s "$output" ]] || fail "$label $view $appearance: empty screenshot"

      logs="$(xcrun simctl spawn "$udid" log show --style compact --start "$started" \
        --predicate 'subsystem == "Saga" AND category == "Launch"' 2>/dev/null || true)"
      grep -qF "Initial view $view with $BOOK_COUNT books" <<<"$logs" \
        || fail "$label $view $appearance: app didn't log 'Initial view $view with $BOOK_COUNT books'"
      if [[ "$view" == "book" ]]; then
        grep -qF "Opened book $READING_TITLE" <<<"$logs" \
          || fail "$label $view $appearance: app didn't open '$READING_TITLE'"
      fi
      echo "  ok    $view $appearance -> ${output#"$ROOT/"}"
    done
  done

  xcrun simctl terminate "$udid" "$SAGA_BUNDLE_ID" >/dev/null 2>&1 || true
  local stored
  stored="$(sqlite3 "$container/Library/Application Support/Saga.sqlite" 'SELECT COUNT(*) FROM ZBOOK')"
  [[ "$stored" == "$BOOK_COUNT" ]] || fail "$label: store has $stored books after the run, expected $BOOK_COUNT"
  echo "  ok    store still has $BOOK_COUNT books"

  local base="$CAPTURES/saga-$label"
  for pair in "home-light book-light" "home-dark book-dark" "home-light home-dark" "book-light book-dark"; do
    read -r a b <<<"$pair"
    [[ "$(shasum <"$base-$a.png")" != "$(shasum <"$base-$b.png")" ]] \
      || fail "$label: $a and $b rendered identically"
  done
  echo "  ok    home, book, light and dark renders all differ"

  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
}

capture_device iphone '^iPhone [0-9]+ Pro$'
capture_device ipad '^iPad Pro 13'

echo "ui-screenshots: wrote $(find "$CAPTURES" -name '*.png' | wc -l | tr -d ' ') screenshots to ${CAPTURES#"$ROOT/"}"
