#!/usr/bin/env bash
# make-identity.sh (make signing-identity): makes "Folio Local Signing", a self-signed code signing
# identity in the login keychain, once per Mac. `make app` then signs with it instead of ad hoc.
#
# Why: an ad hoc signature is a hash of this one build, and macOS privacy (Full Disk Access, Desktop,
# Documents, Downloads) keeps each grant against that hash. Every rebuild then lost the grants and the
# prompts came back. A signature from a fixed certificate gives every build the same designated
# requirement, so the grants stay. The certificate is for this Mac only; it is not an Apple identity.
set -euo pipefail
NAME="Folio Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
    echo "\"$NAME\" is already in the login keychain: nothing to do."
    exit 0
fi

work=$(mktemp -d /private/tmp/folio-signing.XXXXXX)
trap 'mv "$work" "$HOME/.Trash/folio-signing-$(date +%s)" 2>/dev/null || true' EXIT
pass=$(uuidgen)

cat > "$work/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

# /usr/bin/openssl is LibreSSL: its PKCS#12 file is one `security import` reads (OpenSSL 3 needs -legacy).
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$work/cert.cnf" \
    -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" -name "$NAME" \
    -passout "pass:$pass" -out "$work/identity.p12"

# -T: codesign may use the key without asking each time.
security import "$work/identity.p12" -k "$KEYCHAIN" -P "$pass" -T /usr/bin/codesign
# Trusted for code signing (macOS asks for the login password once).
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$work/cert.pem"

security find-identity -v -p codesigning | grep "\"$NAME\"" \
    && echo "made \"$NAME\": make app now signs with it"
