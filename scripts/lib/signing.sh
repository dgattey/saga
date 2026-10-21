# Ad-hoc code signing for macOS releases (scripts/package-release.sh).
# Source from bash: source "$(dirname "$0")/lib/signing.sh"

SAGA_SELF_SIGNED_NAME="${SAGA_SELF_SIGNED_NAME:-Saga Self-Signed}"

# Prints the codesign identity for macOS packaging (defaults to ad-hoc '-').
# Untrusted self-signed X.509 certificates are killed by syspolicyd/amfid on
# macOS Sequoia/Tahoe when quarantined; ad-hoc ('-') works cleanly with
# Gatekeeper "Open Anyway" and Sparkle 2 EdDSA update validation.
resolve_sign_identity() {
  if [[ -n "${SAGA_SIGN_IDENTITY:-}" ]]; then
    printf '%s' "$SAGA_SIGN_IDENTITY"
    return 0
  fi
  printf '%s' '-'
}

sign_identity_is_real() {
  [[ "$(resolve_sign_identity)" != "-" ]]
}

# Locates a tool inside the Sparkle artifact bundle SwiftPM resolves into .build/.
find_sparkle_tool() {
  local tool="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/.build/artifacts/sparkle/Sparkle/bin/$1"
  [[ -x "$tool" ]] || return 1
  printf '%s' "$tool"
}
