#!/bin/bash
# Creates a stable self-signed code-signing identity in the login keychain.
# Run once. After this, every build signs with the same identity, so the macOS
# Screen Recording grant survives rebuilds instead of resetting each time.
set -euo pipefail

IDENTITY="TimeTracker Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if security find-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; then
	echo "Identiteten \"$IDENTITY\" finns redan. Klart."
	exit 0
fi

echo "Skapar självsignerat certifikat \"$IDENTITY\"..."

# X.509 with the code-signing EKU that codesign requires.
cat > "$WORK/cert.conf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $IDENTITY
[ ext ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -new -newkey rsa:2048 -x509 -days 3650 -nodes \
	-keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
	-config "$WORK/cert.conf" >/dev/null 2>&1

openssl pkcs12 -export -out "$WORK/identity.p12" \
	-inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
	-passout pass:timetracker >/dev/null 2>&1

# Import key + cert; -T lets codesign use it without a prompt per build.
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P timetracker \
	-T /usr/bin/codesign >/dev/null

# Allow codesign to read the key non-interactively (this line may ask for your login password).
security set-key-partition-list -S apple-tool:,apple: -s \
	-k "$(security default-keychain | tr -d ' \"')" "$KEYCHAIN" >/dev/null 2>&1 || \
	security set-key-partition-list -S apple-tool:,apple: -s "$KEYCHAIN" >/dev/null 2>&1 || true

echo "Klart. Bygg om appen med ./build.sh så signeras den med \"$IDENTITY\"."
