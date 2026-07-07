#!/bin/bash
# Creates a self-signed code-signing certificate ("WhisperFlow Signing") in the
# login keychain. Signing with a stable identity keeps the app's designated
# requirement constant across rebuilds, so macOS permission grants
# (Accessibility, Microphone) survive instead of resetting every build.
set -euo pipefail

NAME="WhisperFlow Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$NAME"; then
  echo "Signing identity \"$NAME\" already exists."
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
basicConstraints = critical,CA:FALSE
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" 2>/dev/null

/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/cert.p12" -passout pass:whisperflow -name "$NAME"

security import "$TMP/cert.p12" -k "$KEYCHAIN" -P whisperflow -T /usr/bin/codesign

# Trust the certificate for code signing (user trust domain; macOS may show an
# authentication prompt — enter your login password there).
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

echo "Created signing identity \"$NAME\"."
