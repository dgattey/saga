# Self-signed code signing for macOS releases.
# Source from bash: source "$(dirname "$0")/lib/signing.sh"

SAGA_SELF_SIGNED_NAME="${SAGA_SELF_SIGNED_NAME:-Saga Self-Signed}"

# Prints the self-signed codesign identity (SHA-1 hash preferred), or ad-hoc (-) when missing.
resolve_sign_identity() {
  local line
  line="$(security find-identity -v -p codesigning 2>/dev/null | grep -F "\"${SAGA_SELF_SIGNED_NAME}\"" | head -1 || true)"
  if [[ -z "$line" ]]; then
    printf '%s' '-'
    return 0
  fi
  if [[ "$line" =~ ^[[:space:]]*[0-9]+\)[[:space:]]+([0-9A-F]+)[[:space:]]+ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  printf '%s' "$SAGA_SELF_SIGNED_NAME"
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
