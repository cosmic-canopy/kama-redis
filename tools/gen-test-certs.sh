#!/bin/sh
# gen-test-certs.sh — the throwaway PKI the integration server and the tests use, written into
# out/test-certs. It is generated, never tracked: `kama publish` refuses a tracked *.key, and so does the
# registry.
#
#   ca.crt / ca.key              the test CA
#   server.crt / server.key      the server: CN localhost, subjectAltName DNS:localhost, IP:127.0.0.1, IP:::1
#   wronghost.crt / .key         a server certificate for another name: CN and subjectAltName DNS:wrong.example
#   client.crt / client.key      a client certificate, CN kr_cert, signed by the test CA
#   client-enc.key               client.key, encrypted as PKCS#8 (PBES2, AES-256-CBC) under kr_client_key_pw
#   other-ca.crt / other-ca.key  a CA nobody trusts, for the "untrusted" cases
#   other-client.crt / .key      a client certificate signed by the untrusted CA
#
# Every certificate is made with `req` and `x509 -req -extfile`, which OpenSSL and LibreSSL (macOS's
# /usr/bin/openssl) both take the same way. OPENSSL picks the binary (default `openssl`).
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DIR="$ROOT/out/test-certs"
OPENSSL=${OPENSSL:-openssl}

# Bump GENERATION when the set of files changes, so an older out/test-certs is regenerated rather than used.
GENERATION=2
if [ "$(cat "$DIR/.generation" 2>/dev/null)" = "$GENERATION" ] && [ "${1:-}" != "--force" ]; then
    exit 0
fi
rm -rf "$DIR"
mkdir -p "$DIR/work"
cd "$DIR/work"

ossl() { "$OPENSSL" "$@" >/dev/null 2>"err.txt" || { echo "gen-test-certs: $OPENSSL $1 failed:" >&2; cat err.txt >&2; exit 1; }; }

cat > ext.cnf <<'EOF'
[req]
distinguished_name = dn
[dn]
[ca]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
[server]
basicConstraints = CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:localhost,IP:127.0.0.1,IP:::1
[wronghost]
basicConstraints = CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:wrong.example
[client]
basicConstraints = CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = clientAuth
EOF

ca() {  # ca <name> <common name>
    ossl genrsa -out "../$1.key" 2048
    ossl req -x509 -new -key "../$1.key" -days 3650 -subj "/CN=$2" -config ext.cnf -extensions ca -out "../$1.crt"
}
leaf() {  # leaf <name> <common name> <issuer> <extensions>
    ossl genrsa -out "../$1.key" 2048
    ossl req -new -key "../$1.key" -subj "/CN=$2" -config ext.cnf -out "$1.csr"
    ossl x509 -req -in "$1.csr" -CA "../$3.crt" -CAkey "../$3.key" -CAcreateserial -days 3650 \
        -extfile ext.cnf -extensions "$4" -out "../$1.crt"
}

ca   ca           "kama-redis test CA"
ca   other-ca     "kama-redis untrusted CA"
leaf server       localhost  ca       server
leaf wronghost    wrong.example ca    wronghost
leaf client       kr_cert    ca       client
leaf other-client kr_cert    other-ca client
ossl pkcs8 -topk8 -v2 aes-256-cbc -in ../client.key -out ../client-enc.key -passout pass:kr_client_key_pw

# The keys are private to their owner; the server's copy is made readable to the server by start.sh.
chmod 0600 ../*.key
cd .. && rm -rf work
echo "$GENERATION" > .generation
echo "gen-test-certs: wrote $DIR"
