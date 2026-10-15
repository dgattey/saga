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

# Locates a tool inside the resolved Sparkle SwiftPM artifact bundle in DerivedData.
find_sparkle_tool() {
  local tool_name=$1
  local derived_data=${2:-"$HOME/Library/Developer/Xcode/DerivedData"}
  local candidate
  while IFS= read -r candidate; do
    if [[ -x "$candidate" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done < <(find "$derived_data" -path "*/SourcePackages/artifacts/sparkle/Sparkle/bin/${tool_name}" 2>/dev/null || true)
  return 1
}
