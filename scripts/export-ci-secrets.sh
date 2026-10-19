#!/usr/bin/env bash
# Validate Sparkle EdDSA signing key and push GitHub Actions secret (`SPARKLE_ED_PRIVATE_KEY_BASE64`)
# for `release.yml`. Releases use ad-hoc (`-`) code signing with
# `com.apple.security.cs.disable-library-validation` + Sparkle 2 EdDSA update verification.
#
# Usage:
#   ./scripts/export-ci-secrets.sh
#   ./scripts/export-ci-secrets.sh --print-only
#   ./scripts/export-ci-secrets.sh --dry-run
#   ./scripts/export-ci-secrets.sh --skip-sparkle
#   ./scripts/export-ci-secrets.sh --sparkle-key-file /path/to/key
#   ./scripts/export-ci-secrets.sh --repo owner/name
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/signing.sh
source "$ROOT/scripts/lib/signing.sh"

CERT_DIR="$ROOT/.cert"

PRINT_ONLY=false
DRY_RUN=false
SKIP_SPARKLE=false
REPO=""
SPARKLE_KEY_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --print-only) PRINT_ONLY=true ;;
    --dry-run) DRY_RUN=true ;;
    --skip-sparkle) SKIP_SPARKLE=true ;;
    --repo) REPO="${2:?--repo requires owner/name}"; shift ;;
    --sparkle-key-file) SPARKLE_KEY_FILE="${2:?--sparkle-key-file requires a path}"; shift ;;
    -h|--help)
      sed -n '2,11p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "export-ci-secrets: unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

resolve_github_repo() {
  if [[ -n "$REPO" ]]; then
    printf '%s' "$REPO"
    return 0
  fi
  if command -v gh >/dev/null 2>&1 && gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null; then
    return 0
  fi
  local url
  url="$(git -C "$ROOT" remote get-url origin 2>/dev/null)" || true
  if [[ "$url" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
    printf '%s/%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi
  echo "export-ci-secrets: could not detect GitHub repo — use --repo owner/name." >&2
  return 1
}

resolve_sparkle_key_file() {
  if [[ -n "$SPARKLE_KEY_FILE" ]]; then
    [[ -f "$SPARKLE_KEY_FILE" ]] || {
      echo "export-ci-secrets: not found: $SPARKLE_KEY_FILE" >&2
      exit 1
    }
    printf '%s' "$SPARKLE_KEY_FILE"
    return 0
  fi
  local candidate
  for candidate in \
    "$CERT_DIR/sparkle_ed.key" \
    "$ROOT/sparkle_private.key" \
    "$HOME/.config/saga/sparkle_ed.key"; do
    if [[ -f "$candidate" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  local gk
  gk="$(find_sparkle_tool generate_keys || true)"
  mkdir -p "$CERT_DIR"
  if [[ -n "$gk" && -x "$gk" ]] && "$gk" -x "$CERT_DIR/sparkle_ed.key" 2>/dev/null && [[ -f "$CERT_DIR/sparkle_ed.key" ]]; then
    printf '%s' "$CERT_DIR/sparkle_ed.key"
    return 0
  fi
  return 1
}

push_github_secret() {
  local name=$1 value=$2 tmp
  tmp="$(mktemp)"
  printf '%s' "$value" >"$tmp"
  if [[ "$DRY_RUN" == true ]]; then
    echo "export-ci-secrets: [dry-run] would set $name (${#value} chars) on $REPO"
    rm -f "$tmp"
    return 0
  fi
  gh secret set "$name" --repo "$REPO" <"$tmp"
  rm -f "$tmp"
  echo "export-ci-secrets: set $name on $REPO (${#value} chars)"
}

SPARKLE_B64=""
if [[ "$SKIP_SPARKLE" != true ]]; then
  if SPARKLE_PATH="$(resolve_sparkle_key_file)"; then
    SPARKLE_B64="$(base64 <"$SPARKLE_PATH" | tr -d '\n')"
    echo "export-ci-secrets: Sparkle key OK (${#SPARKLE_B64} base64 chars)" >&2
  elif [[ "$DRY_RUN" == true ]]; then
    echo "export-ci-secrets: [dry-run] no local Sparkle key" >&2
  elif command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    _repo="$(resolve_github_repo)"
    if gh secret list --repo "$_repo" 2>/dev/null | awk '{print $1}' | grep -qx SPARKLE_ED_PRIVATE_KEY_BASE64; then
      echo "export-ci-secrets: keeping existing SPARKLE_ED_PRIVATE_KEY_BASE64 on $_repo" >&2
      SKIP_SPARKLE=true
    else
      echo "export-ci-secrets: no Sparkle key — run ./scripts/generate-sparkle-key.sh, then re-run." >&2
      exit 1
    fi
  else
    echo "export-ci-secrets: no Sparkle key; use --skip-sparkle or --sparkle-key-file." >&2
    exit 1
  fi
fi

if [[ "$PRINT_ONLY" == true ]]; then
  [[ -n "$SPARKLE_B64" ]] && echo "SPARKLE_ED_PRIVATE_KEY_BASE64=$SPARKLE_B64"
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "export-ci-secrets: install gh CLI or use --print-only." >&2
  exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "export-ci-secrets: run: gh auth login" >&2
  exit 1
fi

REPO="$(resolve_github_repo)"
echo "export-ci-secrets: pushing to $REPO" >&2
[[ -n "$SPARKLE_B64" ]] && push_github_secret SPARKLE_ED_PRIVATE_KEY_BASE64 "$SPARKLE_B64"
echo "export-ci-secrets: done."
