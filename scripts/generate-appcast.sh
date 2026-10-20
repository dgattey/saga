#!/usr/bin/env bash
# Generate a Sparkle 2 appcast.xml with cumulative versioned HTML release notes inside CDATA.
#
# Delegates cumulative HTML release-notes formatting (new version `<h3>` + carried-forward
# prior versions capped at 10) to `scripts/release-notes.sh`, signs or verifies the release
# archive with Sparkle's tools, and emits `<sparkle:fullReleaseNotesLink>` alongside any
# `generate_appcast --full-release-notes-url` invocation.
#
# Usage:
#   ./scripts/generate-appcast.sh <version> <build> <zip-path-or-bytes> <output-appcast-path> [pub-date]
#
# Environment variables:
#   SAGA_RELEASE_NOTES              — Markdown or HTML release notes for the update item
#   SAGA_PREVIOUS_APPCAST           — Optional path or URL to previous `appcast.xml`
#   SAGA_RELEASES_JSON              — Optional path or JSON string of GitHub Releases
#   SAGA_FETCH_PREVIOUS_NOTES       — Set to `0` to disable network fetches for prior notes (default: `1`)
#   SAGA_MAX_RELEASE_NOTES_VERSIONS — Maximum cumulative versions to keep (default: `10`)
#   SAGA_FULL_RELEASE_NOTES_URL     — Full release notes URL (default: `https://github.com/dgattey/saga/releases`)
#   SAGA_REPO                       — GitHub repository (default: `dgattey/saga`)
#   SPARKLE_ED_KEY_FILE             — Optional path to Sparkle EdDSA private key file for signing
#   SPARKLE_ED_PRIVATE_KEY_BASE64   — Optional base64-encoded Sparkle EdDSA private key
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/signing.sh
source "$ROOT/scripts/lib/signing.sh"

VERSION="${1:?generate-appcast: version is required (arg 1)}"
BUILD_NUMBER="${2:?generate-appcast: build number is required (arg 2)}"
ZIP_INPUT="${3:?generate-appcast: zip path or byte length is required (arg 3)}"
APPCAST_PATH="${4:-$ROOT/dist/release/appcast.xml}"
PUB_DATE="${5:-$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')}"
REPO="${SAGA_REPO:-dgattey/saga}"
FULL_RELEASE_NOTES_URL="${SAGA_FULL_RELEASE_NOTES_URL:-https://github.com/${REPO}/releases}"

if [[ -f "$ZIP_INPUT" ]]; then
  ZIP_PATH="$ZIP_INPUT"
  ZIP_BYTES="$(wc -c <"$ZIP_PATH" | tr -d ' ')"
elif [[ "$ZIP_INPUT" =~ ^[0-9]+$ ]]; then
  ZIP_PATH=""
  ZIP_BYTES="$ZIP_INPUT"
else
  echo "generate-appcast: '$ZIP_INPUT' is neither an existing file nor a byte count" >&2
  exit 1
fi

decode_secret_b64() {
  printf '%s' "$1" | tr -d '[:space:]' | base64 -D 2>/dev/null || printf '%s' "$1" | tr -d '[:space:]' | base64 -d
}

write_sparkle_key_file() {
  local raw_secret="$1" out_file="$2" trimmed decoded_len
  trimmed="$(printf '%s' "$raw_secret" | tr -d '[:space:]')"
  decoded_len="$(decode_secret_b64 "$trimmed" 2>/dev/null | wc -c | tr -d ' ')"
  if [[ "$decoded_len" == "32" || "$decoded_len" == "64" ]]; then
    printf '%s\n' "$trimmed" >"$out_file"
  else
    decode_secret_b64 "$trimmed" >"$out_file"
  fi
}

cleanup_files=()
cleanup() {
  for f in "${cleanup_files[@]:-}"; do
    if [[ -n "$f" && -e "$f" ]]; then
      rm -rf "$f"
    fi
  done
  return 0
}
trap cleanup EXIT

if [[ -z "${SPARKLE_ED_KEY_FILE:-}" && -n "${SPARKLE_ED_PRIVATE_KEY_BASE64:-}" ]]; then
  KEY_FILE="$(mktemp /tmp/saga-sparkle-ed.XXXXXX.key)"
  cleanup_files+=("$KEY_FILE")
  write_sparkle_key_file "$SPARKLE_ED_PRIVATE_KEY_BASE64" "$KEY_FILE"
  export SPARKLE_ED_KEY_FILE="$KEY_FILE"
elif [[ -z "${SPARKLE_ED_KEY_FILE:-}" && -f "$ROOT/.cert/sparkle_ed.key" ]]; then
  export SPARKLE_ED_KEY_FILE="$ROOT/.cert/sparkle_ed.key"
fi

# If APPCAST_PATH already exists locally and SAGA_PREVIOUS_APPCAST is unset, preserve it as the previous appcast source
if [[ -z "${SAGA_PREVIOUS_APPCAST:-}" && -f "$APPCAST_PATH" ]]; then
  PREV_APPCAST_COPY="$(mktemp /tmp/saga-prev-appcast.XXXXXX.xml)"
  cleanup_files+=("$PREV_APPCAST_COPY")
  cp "$APPCAST_PATH" "$PREV_APPCAST_COPY"
  export SAGA_PREVIOUS_APPCAST="$PREV_APPCAST_COPY"
fi

# Format cumulative HTML release notes (new version at top + carried-forward prior versions capped at 10)
NOTES_HTML="$("$ROOT/scripts/release-notes.sh" "$VERSION")"

# Sign the archive with Sparkle's sign_update (via explicit key file or macOS Keychain)
ED_SIGNATURE_ATTR=""
ED_SIG=""
if [[ -n "$ZIP_PATH" ]]; then
  SU_TOOL="$(find_sparkle_tool sign_update || true)"
  if [[ -n "$SU_TOOL" && -x "$SU_TOOL" ]]; then
    if [[ -n "${SPARKLE_ED_KEY_FILE:-}" && -f "${SPARKLE_ED_KEY_FILE}" ]]; then
      if ED_SIG="$("$SU_TOOL" --ed-key-file "$SPARKLE_ED_KEY_FILE" -p "$ZIP_PATH" 2>/dev/null | tr -d '[:space:]')" && [[ -n "$ED_SIG" ]]; then
        ED_SIGNATURE_ATTR=" sparkle:edSignature=\"${ED_SIG}\""
      fi
    elif [[ "${ALLOW_KEYCHAIN_SPARKLE_SIGN:-1}" == "1" ]]; then
      if ED_SIG="$("$SU_TOOL" -p "$ZIP_PATH" 2>/dev/null | tr -d '[:space:]')" && [[ -n "$ED_SIG" ]]; then
        ED_SIGNATURE_ATTR=" sparkle:edSignature=\"${ED_SIG}\""
      fi
    fi
  fi

  # If Sparkle's generate_appcast binary is available and we still need a signature (or to validate flags),
  # pass --full-release-notes-url "https://github.com/dgattey/saga/releases" when supported by generate_appcast -h.
  GA_TOOL="$(find_sparkle_tool generate_appcast || true)"
  if [[ -n "$GA_TOOL" && -x "$GA_TOOL" ]]; then
    GA_ARGS=()
    if "$GA_TOOL" -h 2>&1 | grep -q -- '--full-release-notes-url'; then
      GA_ARGS+=(--full-release-notes-url "$FULL_RELEASE_NOTES_URL")
    fi
    if [[ -z "$ED_SIGNATURE_ATTR" ]]; then
      GA_WORK_DIR="$(mktemp -d /tmp/saga-gen-appcast.XXXXXX)"
      cleanup_files+=("$GA_WORK_DIR")
      cp "$ZIP_PATH" "$GA_WORK_DIR/"
      GA_KEY_ARGS=()
      if [[ -n "${SPARKLE_ED_KEY_FILE:-}" && -f "${SPARKLE_ED_KEY_FILE}" ]]; then
        GA_KEY_ARGS+=(--ed-key-file "$SPARKLE_ED_KEY_FILE")
      fi
      if "$GA_TOOL" "${GA_KEY_ARGS[@]}" "${GA_ARGS[@]}" "$GA_WORK_DIR" >/dev/null 2>&1 && [[ -f "$GA_WORK_DIR/appcast.xml" ]]; then
        GA_SIG="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' "$GA_WORK_DIR/appcast.xml" | head -n 1)"
        if [[ -n "$GA_SIG" ]]; then
          ED_SIG="$GA_SIG"
          ED_SIGNATURE_ATTR=" sparkle:edSignature=\"${ED_SIG}\""
        fi
      fi
    fi
  fi

  if [[ "${REQUIRE_SPARKLE_SIGNATURE:-0}" == "1" && -z "$ED_SIGNATURE_ATTR" ]]; then
    echo "generate-appcast: failed to generate sparkle:edSignature for $ZIP_PATH (ensure SPARKLE_ED_PRIVATE_KEY_BASE64, SPARKLE_ED_KEY_FILE, or Keychain key is configured and sign_update is available)" >&2
    exit 1
  fi

  # Verify the generated Ed25519 signature against the SUPublicEDKey build-macos.sh embeds when OpenSSL 3+ is available
  PUBLIC_KEY_FILE="$ROOT/sparkle-public-key.txt"
  if [[ -n "$ED_SIG" && -f "$PUBLIC_KEY_FILE" ]] && openssl version 2>/dev/null | grep -q '^OpenSSL'; then
    PUB_KEY="$(tr -d '[:space:]' <"$PUBLIC_KEY_FILE")"
    if [[ -n "$PUB_KEY" ]]; then
      TMP_PUB="$(mktemp /tmp/saga-sparkle-pub.XXXXXX.pem)"
      TMP_SIG="$(mktemp /tmp/saga-sparkle-sig.XXXXXX.bin)"
      cleanup_files+=("$TMP_PUB" "$TMP_SIG")
      {
        echo "-----BEGIN PUBLIC KEY-----"
        printf '302a300506032b6570032100%s' "$(decode_secret_b64 "$PUB_KEY" | xxd -p -c 64)" | xxd -r -p | base64
        echo "-----END PUBLIC KEY-----"
      } >"$TMP_PUB"
      decode_secret_b64 "$ED_SIG" >"$TMP_SIG"
      if ! openssl pkeyutl -verify -pubin -inkey "$TMP_PUB" -rawin -in "$ZIP_PATH" -sigfile "$TMP_SIG" >/dev/null 2>&1; then
        echo "generate-appcast: Ed25519 signature does not verify against $PUBLIC_KEY_FILE (private/public key mismatch)" >&2
        exit 1
      fi
    fi
  fi
fi

ZIP_NAME="Saga-${VERSION}.zip"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/v${VERSION}/${ZIP_NAME}"
RELEASE_LINK="https://github.com/${REPO}/releases/tag/v${VERSION}"

mkdir -p "$(dirname "$APPCAST_PATH")"
cat >"$APPCAST_PATH" <<XML
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <title>Saga</title>
    <link>${RELEASE_LINK}</link>
    <item>
      <title>${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <link>${RELEASE_LINK}</link>
      <sparkle:version>${BUILD_NUMBER}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>${FULL_RELEASE_NOTES_URL}</sparkle:fullReleaseNotesLink>
      <description><![CDATA[${NOTES_HTML}]]></description>
      <enclosure url="${DOWNLOAD_URL}" length="${ZIP_BYTES}" type="application/octet-stream"${ED_SIGNATURE_ATTR}/>
    </item>
  </channel>
</rss>
XML
