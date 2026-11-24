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

# --- Create temp build context (assembles every output type) ---
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

echo "Assembling all output configs..."
"$SCRIPT_DIR/prepare-context.sh" "$BUILD_DIR"

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
echo "Test locally (config test with dummy credentials):"
printf '  %s run --rm -e OUTPUT_TYPE=splunk-hec \\\n' "$CONTAINER_CMD"
# shellcheck disable=SC2016  # the $(...) is printed for the user to run
printf '    $(%s splunk-hec | tr "\\n" " ") \\\n' "$(cd "$SCRIPT_DIR/.." && pwd)/test-tools/ci/output-env-vars.sh"
printf '    %s --config.test_and_exit\n' "$IMAGE_NAME:$TAG"
