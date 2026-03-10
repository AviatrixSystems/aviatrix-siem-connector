#!/bin/sh
set -e

CERT_DIR="/etc/stunnel/certs"
mkdir -p "$CERT_DIR"

# Write certs from env vars if set (ECS mode — secrets injected as env vars)
# If files already exist at CERT_DIR (volume mount mode — EC2), skip writing
if [ -n "$TLS_SERVER_CERT" ] && [ ! -f "$CERT_DIR/server.crt" ]; then
  echo "$TLS_SERVER_CERT" > "$CERT_DIR/server.crt"
  echo "$TLS_SERVER_KEY"  > "$CERT_DIR/server.key"
  echo "$TLS_CA_CERT"     > "$CERT_DIR/ca.crt"
fi

# Validate required cert files exist
for f in server.crt server.key ca.crt; do
  if [ ! -f "$CERT_DIR/$f" ]; then
    echo "ERROR: Missing $CERT_DIR/$f"
    echo "Provide certs via env vars (TLS_SERVER_CERT, TLS_SERVER_KEY, TLS_CA_CERT)"
    echo "or mount them as a volume at $CERT_DIR/"
    exit 1
  fi
done

chmod 600 "$CERT_DIR/server.key" 2>/dev/null || true

# Generate stunnel config
cat > /etc/stunnel/stunnel.conf <<EOF
foreground = yes
syslog = no

[syslog-tls]
accept = ${TLS_LISTEN_ADDRESS:-0.0.0.0}:${TLS_PORT:-6514}
connect = 127.0.0.1:${LOGSTASH_PORT:-5000}
cert = $CERT_DIR/server.crt
key = $CERT_DIR/server.key
CAfile = $CERT_DIR/ca.crt
verify = 2
EOF

echo "stunnel: listening on ${TLS_LISTEN_ADDRESS:-0.0.0.0}:${TLS_PORT:-6514} (mTLS) -> 127.0.0.1:${LOGSTASH_PORT:-5000}"
exec stunnel /etc/stunnel/stunnel.conf
