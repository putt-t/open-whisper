#!/usr/bin/env bash
set -euo pipefail

# Removes the self-signed code signing certificate created by codesign-create.sh.

CERT_NAME="${1:-DictationDev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

echo "Removing code signing certificate: $CERT_NAME"

# Delete identity (private key + cert pair)
while security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$CERT_NAME\""; do
  HASH="$(security find-identity -v -p codesigning 2>/dev/null | grep "\"$CERT_NAME\"" | head -1 | awk '{print $2}')"
  security delete-identity -Z "$HASH" 2>/dev/null || true
done

# Delete any remaining trust-only certificates
while security find-certificate -c "$CERT_NAME" -Z "$KEYCHAIN" 2>/dev/null | grep -q "SHA-1"; do
  HASH="$(security find-certificate -c "$CERT_NAME" -Z "$KEYCHAIN" 2>/dev/null | grep "SHA-1" | head -1 | awk '{print $NF}')"
  security delete-certificate -Z "$HASH" 2>/dev/null || true
done

echo
echo "Done. Verify with:"
echo "  security find-identity -v -p codesigning"
echo
echo "Remember to remove DICTATION_CODESIGN_IDENTITY from your .env."
