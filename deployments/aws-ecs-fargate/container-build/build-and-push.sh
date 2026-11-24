#!/usr/bin/env bash
# Build and push Logstash container image to ECR
#
# Usage:
#   ./build-and-push.sh --output-type splunk-hec --ecr-repo 123456789.dkr.ecr.us-east-2.amazonaws.com/avxlog-abc123
#   ./build-and-push.sh --output-type zabbix --ecr-repo <ecr-url> --tag v1.0
#   ./build-and-push.sh --output-type splunk-hec --ecr-repo <ecr-url> --region us-west-2

set -euo pipefail

# --- Defaults ---
OUTPUT_TYPE=""
ECR_REPO=""
TAG=""   # default: content hash of the build context (see below)
REGION="us-east-2"

# --- Parse Args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-type) OUTPUT_TYPE="$2"; shift 2 ;;
    --ecr-repo)    ECR_REPO="$2"; shift 2 ;;
    --tag)         TAG="$2"; shift 2 ;;
    --region)      REGION="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 --output-type <type> --ecr-repo <uri> [--tag <tag>] [--region <region>]"
      echo ""
      echo "Options:"
      echo "  --output-type   Output type (splunk-hec, zabbix, dynatrace, etc.) [required]"
      echo "  --ecr-repo      ECR repository URI [required]"
      echo "  --tag           Image tag (default: cfg-<hash of config, patterns and plugins>)"
      echo "  --region        AWS region (default: us-east-2)"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "$OUTPUT_TYPE" ]]; then
  echo "Error: --output-type is required"
  exit 1
fi

if [[ -z "$ECR_REPO" ]]; then
  echo "Error: --ecr-repo is required"
  exit 1
fi

# --- Detect container runtime (docker or podman) ---
if command -v docker &>/dev/null; then
  CONTAINER_CMD="docker"
elif command -v podman &>/dev/null; then
  CONTAINER_CMD="podman"
else
  echo "Error: neither docker nor podman found in PATH"
  exit 1
fi
echo "Using container runtime: $CONTAINER_CMD"

# --- Resolve paths ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(cd "$DEPLOY_DIR/../.." && pwd)"
LOGSTASH_CONFIGS="$REPO_ROOT/logstash-configs"
ASSEMBLED_CONF="$LOGSTASH_CONFIGS/assembled/${OUTPUT_TYPE}-full.conf"

# --- Plugin map ---
get_extra_plugins() {
  case "$1" in
    zabbix)               echo "logstash-output-zabbix" ;;
    azure-log-ingestion)  echo "microsoft-sentinel-log-analytics-logstash-output-plugin" ;;
    *)                    echo "" ;;
  esac
}

EXTRA_PLUGINS="$(get_extra_plugins "$OUTPUT_TYPE")"

# --- Assemble config ---
# Always reassemble so filter/output edits are never baked in stale.
echo "Assembling config for output type: $OUTPUT_TYPE"
"$LOGSTASH_CONFIGS/scripts/assemble-config.sh" "$OUTPUT_TYPE"

if [[ ! -f "$ASSEMBLED_CONF" ]]; then
  echo "Error: Assembled config not found at $ASSEMBLED_CONF"
  exit 1
fi

# --- Create temp build context ---
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

mkdir -p "$BUILD_DIR/pipeline" "$BUILD_DIR/patterns"
cp "$ASSEMBLED_CONF" "$BUILD_DIR/pipeline/logstash.conf"
cp "$LOGSTASH_CONFIGS/patterns/"* "$BUILD_DIR/patterns/"
cp "$SCRIPT_DIR/Dockerfile" "$BUILD_DIR/"
echo "$EXTRA_PLUGINS" > "$BUILD_DIR/.plugins"

# --- Default tag: content hash ---
# A mutable tag like "latest" never changes the task definition, so ECS would
# keep running the old image. A content-addressed tag changes whenever the
# config, patterns, Dockerfile or plugin list change.
if [[ -z "$TAG" ]]; then
  if command -v sha256sum &>/dev/null; then SHA_CMD=(sha256sum); else SHA_CMD=(shasum -a 256); fi
  CONTENT_HASH="$(cd "$BUILD_DIR" && find . -type f | LC_ALL=C sort | xargs "${SHA_CMD[@]}" | "${SHA_CMD[@]}" | cut -c1-12)"
  TAG="cfg-$CONTENT_HASH"
fi

echo ""
echo "Build context:"
echo "  Config:  $ASSEMBLED_CONF"
echo "  Plugins: ${EXTRA_PLUGINS:-none}"
echo "  Tag:     $ECR_REPO:$TAG"
echo ""

# --- Build image ---
$CONTAINER_CMD build \
  --platform linux/amd64 \
  --build-arg EXTRA_PLUGINS="$EXTRA_PLUGINS" \
  -t "$ECR_REPO:$TAG" \
  "$BUILD_DIR"

# --- Push to ECR ---
ECR_DOMAIN="${ECR_REPO%%/*}"

echo ""
echo "Logging in to ECR: $ECR_DOMAIN"
aws ecr get-login-password --region "$REGION" | $CONTAINER_CMD login --username AWS --password-stdin "$ECR_DOMAIN"

echo "Pushing $ECR_REPO:$TAG"
$CONTAINER_CMD push "$ECR_REPO:$TAG"

echo ""
echo "Done! Image pushed to $ECR_REPO:$TAG"
echo "Set container_image = \"$ECR_REPO:$TAG\" in terraform.tfvars and run 'terraform apply'"
