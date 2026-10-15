#!/usr/bin/env bash
# Create (or refresh) a self-signed code-signing certificate for Saga releases.
#
# Sparkle can install updates only when the new .app is signed with the same identity as the
# running app. A stable self-signed cert in the login keychain satisfies that.
#
# Outputs (gitignored):
#   .cert/saga.crt   — trust this once per Mac
#   .cert/saga.p12   — import into CI via GitHub secrets (see below)
#
# GitHub Actions secrets (base64 the p12; never commit the file):
#   SAGA_CODESIGN_P12_BASE64
#   SAGA_CODESIGN_P12_PASSWORD
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/signing.sh
source "$ROOT/scripts/lib/signing.sh"

CERT_DIR="$ROOT/.cert"
NAME="$SAGA_SELF_SIGNED_NAME"
CN="Saga Self-Signed"
DAYS=3650
P12_PASS="${SAGA_CODESIGN_P12_PASSWORD:-saga}"

mkdir -p "$CERT_DIR"
KEY="$CERT_DIR/key.pem"
CRT="$CERT_DIR/saga.crt"
P12="$CERT_DIR/saga.p12"
CSR="$CERT_DIR/cert.csr"
EXT="$CERT_DIR/v3.ext"

cat >"$EXT" <<EOF
basicConstraints = CA:FALSE
keyUsage = digitalSignature
extendedKeyUsage = codeSigning
EOF

if [[ ! -f "$KEY" ]]; then
  openssl genrsa -out "$KEY" 2048
fi

openssl req -new -key "$KEY" -out "$CSR" -subj "/CN=${CN}/O=Saga/C=US"
openssl x509 -req -in "$CSR" -signkey "$KEY" -sha256 -days "$DAYS" -out "$CRT" -extfile "$EXT"
openssl pkcs12 -export -legacy \
  -inkey "$KEY" -in "$CRT" -out "$P12" \
  -passout "pass:${P12_PASS}" \
  -name "$NAME" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES

# Replace any prior import with the same common name.
security delete-identity -c "$CN" 2>/dev/null || true
security import "$P12" -k ~/Library/Keychains/login.keychain-db -P "$P12_PASS" \
  -T /usr/bin/codesign -T /usr/bin/security -T /usr/bin/productbuild

security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k ~/Library/Keychains/login.keychain-db

echo "setup-self-signed-cert: imported \"$NAME\""
security find-identity -v -p codesigning | grep -F "$NAME" || true
echo
echo "Trust the cert once on this Mac (admin password):"
echo "  sudo security add-trusted-cert -d -r trustAsRoot -k /Library/Keychains/System.keychain \"$CRT\""
echo
echo "Push CI secrets to GitHub:"
echo "  ./scripts/export-ci-secrets.sh"
