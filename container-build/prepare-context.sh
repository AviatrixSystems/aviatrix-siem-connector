#!/usr/bin/env bash
# prepare-context.sh - Build the GHCR image build context in <dir>.
#
# Assembles every output type found under logstash-configs/outputs/ (no
# hardcoded list) into <dir>/configs/, copies the grok patterns, the
# entrypoint and Dockerfile.ghcr (as <dir>/Dockerfile).
# Used by build-ghcr.sh and the GitHub workflows.
#
# Usage: ./prepare-context.sh <dir>

set -euo pipefail

DEST="${1:?Usage: prepare-context.sh <dir>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGSTASH_CONFIGS="$(cd "$SCRIPT_DIR/../logstash-configs" && pwd)"

mkdir -p "$DEST/configs" "$DEST/patterns"
"$LOGSTASH_CONFIGS/scripts/assemble-config.sh" --all "$DEST/configs"
cp "$LOGSTASH_CONFIGS/patterns/"* "$DEST/patterns/"
cp "$SCRIPT_DIR/entrypoint.sh" "$DEST/"
cp "$SCRIPT_DIR/Dockerfile.ghcr" "$DEST/Dockerfile"
