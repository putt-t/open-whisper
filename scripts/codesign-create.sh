#!/usr/bin/env bash
set -euo pipefail

# Creates a self-signed code signing certificate called "DictationDev", this for macOS permissions persist across rebuilds.

CERT_NAME="${1:-DictationDev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
TMPDIR_CERT="$(mktemp -d)"

KEY="$TMPDIR_CERT/dev.key"
CERT="$TMPDIR_CERT/dev.pem"
P12="$TMPDIR_CERT/dev.p12"
P12_PASS="$(openssl rand -hex 12)"

cleanup() { rm -rf "$TMPDIR_CERT"; }
trap cleanup EXIT

# Check if identity already exists
if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$CERT_NAME\""; then
  echo "Certificate \"$CERT_NAME\" already exists."
  echo "To recreate it, run ./scripts/codesign-remove.sh first."
  exit 0
fi

echo "Creating code signing certificate: $CERT_NAME"

openssl req -x509 -newkey rsa:2048 \
  -keyout "$KEY" -out "$CERT" \
  -days 3650 -nodes -subj "/CN=$CERT_NAME" \
  -addext "keyUsage=digitalSignature" \
  -addext "extendedKeyUsage=codeSigning" 2>/dev/null

openssl pkcs12 -export -out "$P12" \
  -inkey "$KEY" -in "$CERT" \
  -passout "pass:$P12_PASS" -legacy 2>/dev/null

security import "$P12" -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$CERT"

echo
echo "Done. Verify with:"
echo "  security find-identity -v -p codesigning"
echo
echo "Add this to your .env:"
echo "  DICTATION_CODESIGN_IDENTITY=$CERT_NAME"
