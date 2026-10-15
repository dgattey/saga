#!/usr/bin/env bash
# One-time: create or read the EdDSA key pair Sparkle uses to sign app updates.
#
# The PRIVATE key is stored in your login keychain (never leaves this machine, never committed).
# The PUBLIC key is written to Saga/Saga/Config/sparkle-public-key.txt and Info.plist (SUPublicEDKey).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/signing.sh
source "$ROOT/scripts/lib/signing.sh"

OUT="$ROOT/Saga/Saga/Config/sparkle-public-key.txt"

GK="$(find_sparkle_tool generate_keys || true)"
if [[ -z "$GK" || ! -x "$GK" ]]; then
  echo "generate-sparkle-key: Sparkle generate_keys not found in DerivedData. Run './run app -b' first." >&2
  exit 1
fi

# Idempotent: creates the keychain private key only if one does not already exist.
"$GK" >/dev/null

PUB="$("$GK" -p | tr -d '[:space:]')"
if [[ -z "$PUB" ]]; then
  echo "generate-sparkle-key: could not read the public key from the keychain" >&2
  exit 1
fi

printf '%s\n' "$PUB" >"$OUT"
echo "Wrote public key -> $OUT"
echo "  $PUB"
