#!/bin/sh
set -eu

CERT_DIR="/etc/stunnel/certs"
mkdir -p "$CERT_DIR"

TLS_SERVER_CERT="${TLS_SERVER_CERT:-}"
TLS_SERVER_KEY="${TLS_SERVER_KEY:-}"
TLS_CA_CERT="${TLS_CA_CERT:-}"
LOGSTASH_HOST="${LOGSTASH_HOST:-127.0.0.1}"
LOGSTASH_PORT="${LOGSTASH_PORT:-5000}"
TLS_LISTEN_ADDRESS="${TLS_LISTEN_ADDRESS:-0.0.0.0}"
TLS_PORT="${TLS_PORT:-6514}"

# Env mode (ECS: secrets injected as env vars): all three must be set, and the
# files are rewritten on every start so rotated secrets take effect on restart.
# Volume mode (EC2: certs mounted at CERT_DIR): leave all three env vars unset.
if [ -n "$TLS_SERVER_CERT" ] || [ -n "$TLS_SERVER_KEY" ] || [ -n "$TLS_CA_CERT" ]; then
  missing=""
  [ -n "$TLS_SERVER_CERT" ] || missing="$missing TLS_SERVER_CERT"
  [ -n "$TLS_SERVER_KEY" ]  || missing="$missing TLS_SERVER_KEY"
  [ -n "$TLS_CA_CERT" ]     || missing="$missing TLS_CA_CERT"
  if [ -n "$missing" ]; then
    echo "ERROR: TLS env mode needs all of TLS_SERVER_CERT, TLS_SERVER_KEY and TLS_CA_CERT; empty:$missing" >&2
    exit 1
  fi
  (
    umask 077
    printf '%s\n' "$TLS_SERVER_CERT" > "$CERT_DIR/server.crt"
    printf '%s\n' "$TLS_SERVER_KEY"  > "$CERT_DIR/server.key"
    printf '%s\n' "$TLS_CA_CERT"     > "$CERT_DIR/ca.crt"
  )
fi

# Validate required cert files: present, non-empty and PEM-shaped
for f in server.crt server.key ca.crt; do
  if [ ! -s "$CERT_DIR/$f" ]; then
    echo "ERROR: Missing or empty $CERT_DIR/$f" >&2
    echo "Provide certs via env vars (TLS_SERVER_CERT, TLS_SERVER_KEY, TLS_CA_CERT)" >&2
    echo "or mount them as a volume at $CERT_DIR/" >&2
    exit 1
  fi
done
for f in server.crt ca.crt; do
  if ! grep -q -- "-----BEGIN CERTIFICATE-----" "$CERT_DIR/$f"; then
    echo "ERROR: $CERT_DIR/$f is not a PEM certificate" >&2
    exit 1
  fi
done
if ! grep -q -- "-----BEGIN .*PRIVATE KEY-----" "$CERT_DIR/server.key"; then
  echo "ERROR: $CERT_DIR/server.key is not a PEM private key" >&2
  exit 1
fi

chmod 600 "$CERT_DIR/server.key" 2>/dev/null || true

# Drop root after the keys are loaded when the package's stunnel user exists.
PRIV_DROP=""
if id stunnel >/dev/null 2>&1; then
  PRIV_DROP="setuid = stunnel
setgid = stunnel"
fi

# Generate stunnel config
cat > /etc/stunnel/stunnel.conf <<EOF
foreground = yes
syslog = no
pid =
$PRIV_DROP

[syslog-tls]
accept = ${TLS_LISTEN_ADDRESS}:${TLS_PORT}
connect = ${LOGSTASH_HOST}:${LOGSTASH_PORT}
cert = $CERT_DIR/server.crt
key = $CERT_DIR/server.key
CAfile = $CERT_DIR/ca.crt
verify = 2
EOF

echo "stunnel: listening on ${TLS_LISTEN_ADDRESS}:${TLS_PORT} (mTLS) -> ${LOGSTASH_HOST}:${LOGSTASH_PORT}"
exec stunnel /etc/stunnel/stunnel.conf
