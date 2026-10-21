# Build settings shared by scripts/build-macos.sh and scripts/build-ios-sim.sh.
# Source from bash: source "$ROOT/scripts/lib/app-config.sh"

SAGA_BUNDLE_ID="com.dylangattey.Saga"
SAGA_MIN_OS="26.0"
# Served from server/public/appcast.xml. Releases up to 1.6.2 poll the GitHub Releases feed; the
# latest GitHub release carries those installs onto this one.
SAGA_FEED_URL="https://saga.gattey.com/appcast.xml"
SAGA_SOURCES="$ROOT/Saga/Saga"

# Contentful credentials come from the environment, then the gitignored Config.xcconfig that
# `run bootstrap` / `run config` write. Compiling never contacts Contentful, so builds without
# credentials get the same "placeholder" values published releases have always shipped.
saga_config_value() {
  local key="$1" fallback="$2" value="${!1:-}" config_file="$ROOT/Config.xcconfig"
  if [[ -z "$value" && -f "$config_file" ]]; then
    value="$(sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//p" "$config_file" | tail -1)"
    value="${value%"${value##*[![:space:]]}"}"
  fi
  printf '%s' "${value:-$fallback}"
}

# Adds the credential keys BundleKey reads; plutil escapes values that could break the XML.
saga_insert_credentials() {
  local plist="$1"
  plutil -insert ContentfulSpaceId -string "$(saga_config_value CONTENTFUL_SPACE_ID placeholder)" "$plist"
  plutil -insert ContentfulAccessToken -string "$(saga_config_value CONTENTFUL_ACCESS_TOKEN placeholder)" "$plist"
  plutil -insert SagaAPISecret -string "$(saga_config_value SAGA_API_SECRET "")" "$plist"
}
