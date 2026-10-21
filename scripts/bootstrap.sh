#!/usr/bin/env bash
# Write Config.xcconfig (gitignored) with dev Contentful credentials from the 1Password `saga` vault.
# devkit puts them in the dev app's Info.plist ([local-values] in DylApp.toml); environment variables
# with the same names win over the file. Values are never printed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$ROOT/Config.xcconfig"
VAULT="saga"

brew bundle --file "$ROOT/Brewfile"
command -v mise >/dev/null && (cd "$ROOT" && mise install)

# Vault items are named after Contentful's APIs. PersistenceService uses the delivery host, so it
# needs the delivery key, not the preview or management token also in the vault.
op whoami >/dev/null 2>&1 || eval "$(op signin --account my.1password.com)"
space_id="$(op read "op://$VAULT/CONTENTFUL_SPACE_ID/value")"
access_token="$(op read "op://$VAULT/CONTENTFUL_DELIVERY_API_KEY/value")"
api_secret="${SAGA_API_SECRET:-$(op read "op://$VAULT/SAGA_API_SECRET/value" 2>/dev/null || true)}"

umask 077
cat >"$CONFIG" <<EOF
// Written by ./run bootstrap. Gitignored; never commit.
CONTENTFUL_SPACE_ID = $space_id
CONTENTFUL_ACCESS_TOKEN = $access_token
SAGA_API_SECRET = $api_secret
EOF
echo "bootstrap: wrote $CONFIG"
