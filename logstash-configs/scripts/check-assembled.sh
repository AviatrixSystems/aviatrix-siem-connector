#!/bin/bash
# check-assembled.sh - Fail if the committed assembled/ configs are stale.
#
# Assembles every output type into a temp directory and compares the result
# with logstash-configs/assembled/*-full.conf. Also fails on assembled files
# whose output type no longer exists. Deployments upload the committed files
# directly, so a filter/output change that was not reassembled would otherwise
# ship silently.
#
# Usage: ./check-assembled.sh
# Fix a failure with: ./scripts/assemble-config.sh --all

set -euo pipefail
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")"
ASSEMBLED="$CONFIG_DIR/assembled"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

"$SCRIPT_DIR/assemble-config.sh" --all "$TMP_DIR" >/dev/null

FAIL=0
for fresh in "$TMP_DIR"/*-full.conf; do
    name="$(basename "$fresh")"
    committed="$ASSEMBLED/$name"
    if [[ ! -f "$committed" ]]; then
        echo "FAIL: assembled/$name is missing"
        FAIL=1
    elif ! diff -u "$committed" "$fresh" > "$TMP_DIR/$name.diff"; then
        echo "FAIL: assembled/$name is stale (diff vs fresh assembly, first 40 lines):"
        head -40 "$TMP_DIR/$name.diff"
        FAIL=1
    else
        echo "PASS: assembled/$name"
    fi
done

for committed in "$ASSEMBLED"/*-full.conf; do
    name="$(basename "$committed")"
    if [[ ! -f "$TMP_DIR/$name" ]]; then
        echo "FAIL: assembled/$name has no outputs/${name%-full.conf}/output.conf"
        FAIL=1
    fi
done

if [[ "$FAIL" -ne 0 ]]; then
    echo ""
    echo "Regenerate with: logstash-configs/scripts/assemble-config.sh --all"
    exit 1
fi
echo "All assembled configs match a fresh assembly."
