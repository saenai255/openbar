#!/bin/bash
# Creates a self-signed "OpenBar Code Signing" identity in the login keychain.
# Signing every build with the same identity lets macOS keep Accessibility and
# Screen Recording grants across rebuilds. Remove later with:
#   security delete-identity -c "OpenBar Code Signing" ~/Library/Keychains/login.keychain-db
set -euo pipefail

NAME="OpenBar Code Signing"
for existing in "$NAME" "Zubar Code Signing"; do
    if security find-identity -p codesigning | grep -q "$existing"; then
        echo "\"$existing\" already exists."
        exit 0
    fi
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
PASS="$(openssl rand -hex 12)"
LEGACY=""
if openssl version | grep -q "^OpenSSL 3"; then LEGACY="-legacy"; fi
openssl pkcs12 -export $LEGACY -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
    -out "$TMP/id.p12" -passout "pass:$PASS"
security import "$TMP/id.p12" -k ~/Library/Keychains/login.keychain-db -P "$PASS" -T /usr/bin/codesign

echo "Created \"$NAME\". Rebuild with ./scripts/build-app.sh"
