#!/usr/bin/env bash
# Generate a Sparkle 2 appcast.xml with clean, scannable HTML release notes inside CDATA.
#
# Converts Markdown release notes (`# Release notes`, `# Highlights`, or `# What changed?`)
# into styled HTML (`<ul><li style="margin-bottom: 6px; line-height: 1.45;">...</li></ul>`,
# `<code>...</code>`, `<strong>...</strong>`) and wraps them in `<description><![CDATA[...]]></description>`.
#
# Usage:
#   ./scripts/generate-appcast.sh <version> <build> <zip-path-or-bytes> <output-appcast-path> [pub-date]
#
# Environment variables:
#   SAGA_RELEASE_NOTES            — Markdown or HTML release notes for the update item
#   SAGA_REPO                     — GitHub repository (default: dgattey/saga)
#   SPARKLE_ED_KEY_FILE           — Optional path to Sparkle EdDSA private key file for signing
#   SPARKLE_ED_PRIVATE_KEY_BASE64 — Optional base64-encoded Sparkle EdDSA private key
#   DERIVED_DATA                  — Optional DerivedData directory to locate Sparkle's sign_update
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
  decode_secret_b64 "$SPARKLE_ED_PRIVATE_KEY_BASE64" >"$KEY_FILE"
  export SPARKLE_ED_KEY_FILE="$KEY_FILE"
elif [[ -z "${SPARKLE_ED_KEY_FILE:-}" && -f "$ROOT/.cert/sparkle_ed.key" ]]; then
  export SPARKLE_ED_KEY_FILE="$ROOT/.cert/sparkle_ed.key"
fi

# Format Markdown release notes into clean, scannable HTML suitable for Sparkle's WebKit view.
format_release_notes_html() {
  python3 - "$VERSION" <<'PY'
import html
import os
import re
import sys

version = sys.argv[1]
raw = os.environ.get("SAGA_RELEASE_NOTES", "").strip()

# Strip HTML comments (e.g. CURSOR_AGENT_PR_BODY markers)
raw = re.sub(r"<!--[\s\S]*?-->", "", raw).strip()

# If full PR body was passed, prefer # Release notes -> # Highlights -> # What changed?
def extract_section(text: str, heading: str) -> str:
    lines = text.splitlines()
    in_section = False
    collected = []
    heading_re = re.compile(rf"^#+\s*{re.escape(heading)}\s*$", re.IGNORECASE)
    any_heading_re = re.compile(r"^#+\s+\S")
    hr_re = re.compile(r"^-+\s*$")
    for line in lines:
        if heading_re.match(line.strip()):
            in_section = True
            continue
        if in_section:
            if any_heading_re.match(line.strip()) or hr_re.match(line.strip()):
                break
            collected.append(line)
    # Filter out bare '-' placeholder lines
    cleaned = [l for l in collected if not re.match(r"^\s*[-*]\s*$", l)]
    return "\n".join(cleaned).strip()

for section_name in ("Release notes", "Highlights", "What changed?"):
    extracted = extract_section(raw, section_name)
    if extracted:
        raw = extracted
        break

# If already HTML with <ul> or <p>, keep it as-is
if re.search(r"<(ul|ol|li|p)\b", raw, re.IGNORECASE):
    print(raw)
    sys.exit(0)

PATH_EXT_RE = re.compile(
    r"^("
    r"[/\.]\S+|"
    r"(?:Saga|scripts|server|\.github)/\S*|"
    r"\S+\.(?:swift|ts|tsx|js|mjs|css|json|yml|yaml|sh|md|plist|entitlements|pbxproj|xcframework|png|jpg|jpeg|svg|ico|xml)|"
    r"npm\s+test"
    r")$"
)

def is_noise_paren(inner: str) -> bool:
    # Split on ',', 'and', 'or' and check if all parts are backticked/bare repo file paths
    cleaned = inner.strip()
    if not cleaned:
        return True
    parts = re.split(r"\s*(?:,|\band\b|\bor\b)\s*", cleaned)
    for part in parts:
        token = part.strip().strip("`").strip()
        if not token or not PATH_EXT_RE.match(token):
            return False
    return True

def strip_file_path_parens(text: str) -> str:
    def repl(match: re.Match) -> str:
        inner = match.group(1)
        if is_noise_paren(inner):
            return ""
        return match.group(0)
    out = re.sub(r"\s*\(([^()]+)\)", repl, text)
    # Collapse double spaces before punctuation
    out = re.sub(r"\s+([,.;:])", r"\1", out)
    out = re.sub(r"  +", " ", out)
    return out.strip()

def render_inline(text: str) -> str:
    text = strip_file_path_parens(text)
    escaped = html.escape(text, quote=False)
    # Convert markdown links [label](https://...)
    escaped = re.sub(
        r"\[([^\]]+)\]\((https?://[^\s)]+)\)",
        r'<a href="\2">\1</a>',
        escaped,
    )
    # Convert **bold**
    escaped = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", escaped)
    # Convert `code`
    escaped = re.sub(r"`([^`]+)`", r"<code>\1</code>", escaped)
    return escaped

lines = raw.splitlines()
bullets = []
paragraphs = []
current_bullet = None

for line in lines:
    stripped = line.strip()
    if not stripped:
        if current_bullet is not None:
            bullets.append(current_bullet)
            current_bullet = None
        continue
    # Skip standalone markdown images or raw image/video tags
    if re.match(r"^!\[[^\]]*\]\([^)]+\)$", stripped) or re.match(r"^<(?:img|video)\b", stripped, re.IGNORECASE):
        continue
    # Skip markdown headings
    if re.match(r"^#+\s+", stripped):
        continue
    bullet_match = re.match(r"^[-*]\s+(.+)$", stripped)
    if bullet_match:
        if current_bullet is not None:
            bullets.append(current_bullet)
        current_bullet = bullet_match.group(1).strip()
    elif current_bullet is not None:
        current_bullet = f"{current_bullet} {stripped}"
    else:
        paragraphs.append(stripped)

if current_bullet is not None:
    bullets.append(current_bullet)

out_parts = []
if paragraphs:
    for p in paragraphs:
        out_parts.append(f'<p style="margin: 0 0 8px 0; line-height: 1.45;">{render_inline(p)}</p>')
if bullets:
    out_parts.append("<ul>")
    for b in bullets:
        out_parts.append(f'  <li style="margin-bottom: 6px; line-height: 1.45;">{render_inline(b)}</li>')
    out_parts.append("</ul>")

if not out_parts:
    out_parts.append(f'<p style="margin: 0; line-height: 1.45;">Release v{html.escape(version)}</p>')

print("\n".join(out_parts))
PY
}

NOTES_HTML="$(format_release_notes_html)"

# Sign the archive with Sparkle's sign_update (via explicit key file or macOS Keychain)
ED_SIGNATURE_ATTR=""
ED_SIG=""
if [[ -n "$ZIP_PATH" ]]; then
  SU_TOOL="$(find_sparkle_tool sign_update "${DERIVED_DATA:-}" || find_sparkle_tool sign_update || true)"
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

  if [[ "${REQUIRE_SPARKLE_SIGNATURE:-0}" == "1" && -z "$ED_SIGNATURE_ATTR" ]]; then
    echo "generate-appcast: failed to generate sparkle:edSignature for $ZIP_PATH (ensure SPARKLE_ED_PRIVATE_KEY_BASE64, SPARKLE_ED_KEY_FILE, or Keychain key is configured and sign_update is available)" >&2
    exit 1
  fi

  # Verify the generated Ed25519 signature against SUPublicEDKey in Info.plist when OpenSSL 3+ is available
  INFO_PLIST="$ROOT/Saga/Saga/Config/Info.plist"
  if [[ -n "$ED_SIG" && -f "$INFO_PLIST" && -x /usr/libexec/PlistBuddy ]] && openssl version 2>/dev/null | grep -q '^OpenSSL'; then
    PUB_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$INFO_PLIST" 2>/dev/null | tr -d '[:space:]' || true)"
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
        echo "generate-appcast: Ed25519 signature does not verify against SUPublicEDKey in $INFO_PLIST (private/public key mismatch)" >&2
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
      <description><![CDATA[${NOTES_HTML}]]></description>
      <enclosure url="${DOWNLOAD_URL}" length="${ZIP_BYTES}" type="application/octet-stream"${ED_SIGNATURE_ATTR}/>
    </item>
  </channel>
</rss>
XML
