#!/usr/bin/env bash
# Build the TLS sidecar image locally
#
# Usage:
#   ./build.sh                    # Build with tag "local"
#   ./build.sh --tag v1.0.0       # Build with specific tag

set -euo pipefail

TAG="local"
IMAGE_NAME="ghcr.io/aviatrixsystems/siem-connector-tls"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) TAG="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--tag <tag>]"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if command -v docker &>/dev/null; then
  CONTAINER_CMD="docker"
elif command -v podman &>/dev/null; then
  CONTAINER_CMD="podman"
else
  echo "Error: neither docker nor podman found"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

$CONTAINER_CMD build \
  --platform linux/amd64 \
  -t "$IMAGE_NAME:$TAG" \
  "$SCRIPT_DIR"

echo ""
echo "Done! Image built: $IMAGE_NAME:$TAG"
