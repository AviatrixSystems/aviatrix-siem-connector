#!/usr/bin/env bash
# Build the GHCR fat image locally for testing
#
# Usage:
#   ./build-ghcr.sh                    # Build with tag "local"
#   ./build-ghcr.sh --tag v1.0.0       # Build with specific tag

set -euo pipefail

TAG="local"
IMAGE_NAME="ghcr.io/aviatrixsystems/aviatrix-siem-connector"

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

# --- Detect container runtime ---
if command -v docker &>/dev/null; then
  CONTAINER_CMD="docker"
elif command -v podman &>/dev/null; then
  CONTAINER_CMD="podman"
else
  echo "Error: neither docker nor podman found"
  exit 1
fi

# --- Resolve paths ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOGSTASH_CONFIGS="$REPO_ROOT/logstash-configs"

# --- Assemble all configs ---
echo "Assembling all output configs..."
OUTPUT_TYPES=(splunk-hec dynatrace dynatrace-metrics dynatrace-logs zabbix azure-log-ingestion webhook-test ci-test)
for ot in "${OUTPUT_TYPES[@]}"; do
  if [[ -d "$LOGSTASH_CONFIGS/outputs/$ot" ]]; then
    "$LOGSTASH_CONFIGS/scripts/assemble-config.sh" "$ot" >/dev/null
  fi
done

# --- Create temp build context ---
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

mkdir -p "$BUILD_DIR/configs" "$BUILD_DIR/patterns"
cp "$LOGSTASH_CONFIGS/assembled/"*-full.conf "$BUILD_DIR/configs/"
cp "$LOGSTASH_CONFIGS/patterns/"* "$BUILD_DIR/patterns/"
cp "$SCRIPT_DIR/entrypoint.sh" "$BUILD_DIR/"
cp "$SCRIPT_DIR/Dockerfile.ghcr" "$BUILD_DIR/Dockerfile"

echo ""
echo "Build context:"
echo "  Configs: $(ls "$BUILD_DIR/configs/" | wc -l | tr -d ' ') assembled configs"
echo "  Tag:     $IMAGE_NAME:$TAG"
echo ""

# --- Build ---
$CONTAINER_CMD build \
  --platform linux/amd64 \
  -t "$IMAGE_NAME:$TAG" \
  "$BUILD_DIR"

echo ""
echo "Done! Image built: $IMAGE_NAME:$TAG"
echo ""
echo "Test locally:"
echo "  $CONTAINER_CMD run --rm -e OUTPUT_TYPE=splunk-hec $IMAGE_NAME:$TAG logstash --config.test_and_exit"
