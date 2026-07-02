#!/usr/bin/env bash
set -euo pipefail

CERT_NAME="${VOICEINK_LOCAL_SIGNING_NAME:-VoiceInk Local Signing}"
KEYCHAIN="${VOICEINK_LOCAL_SIGNING_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
DAYS="${VOICEINK_LOCAL_SIGNING_DAYS:-3650}"
P12_PASSWORD="${VOICEINK_LOCAL_SIGNING_P12_PASSWORD:-voiceink-local-signing}"

if security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -F "\"$CERT_NAME\"" >/dev/null; then
  echo "Code signing identity already exists: $CERT_NAME"
  exit 0
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

OPENSSL_CONFIG="$WORKDIR/codesign.cnf"
PRIVATE_KEY="$WORKDIR/voiceink-local-signing.key.pem"
CERTIFICATE="$WORKDIR/voiceink-local-signing.cert.pem"
IDENTITY="$WORKDIR/voiceink-local-signing.p12"

cat > "$OPENSSL_CONFIG" <<EOF
[ req ]
default_bits = 2048
distinguished_name = req_distinguished_name
x509_extensions = codesign_ext
prompt = no

[ req_distinguished_name ]
CN = $CERT_NAME

[ codesign_ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

openssl req \
  -new \
  -newkey rsa:2048 \
  -nodes \
  -keyout "$PRIVATE_KEY" \
  -x509 \
  -days "$DAYS" \
  -out "$CERTIFICATE" \
  -config "$OPENSSL_CONFIG" \
  -sha256 >/dev/null 2>&1

openssl pkcs12 \
  -export \
  -inkey "$PRIVATE_KEY" \
  -in "$CERTIFICATE" \
  -out "$IDENTITY" \
  -name "$CERT_NAME" \
  -passout "pass:$P12_PASSWORD" >/dev/null 2>&1

security import "$IDENTITY" \
  -k "$KEYCHAIN" \
  -P "$P12_PASSWORD" \
  -f pkcs12 \
  -A \
  -T /usr/bin/codesign \
  -T /usr/bin/security >/dev/null

security add-trusted-cert \
  -r trustRoot \
  -p codeSign \
  -k "$KEYCHAIN" \
  "$CERTIFICATE" >/dev/null

if security find-identity -v -p codesigning "$KEYCHAIN" | grep -F "\"$CERT_NAME\"" >/dev/null; then
  echo "Created code signing identity: $CERT_NAME"
else
  echo "Created certificate, but macOS did not report it as a valid code signing identity." >&2
  exit 1
fi
