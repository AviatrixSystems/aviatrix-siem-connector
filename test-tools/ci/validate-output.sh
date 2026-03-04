#!/bin/bash
# validate-output.sh - Validate Logstash E2E test output
# Usage: ./validate-output.sh <output.jsonl> <test-samples.log>
set -euo pipefail

OUTPUT_FILE="${1:?Usage: validate-output.sh <output.jsonl> <test-samples.log>}"
SAMPLE_FILE="${2:?Usage: validate-output.sh <output.jsonl> <test-samples.log>}"

PASS=0
FAIL=0

check() {
    local desc="$1"
    local result="$2"
    if [[ "$result" == "true" ]]; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc"
        ((FAIL++))
    fi
}

echo "=== Logstash E2E Output Validation ==="
echo "Output file: $OUTPUT_FILE"
echo "Sample file: $SAMPLE_FILE"
echo ""

# Count input lines (non-empty, non-comment)
INPUT_COUNT=$(grep -c '^[^#]' "$SAMPLE_FILE" | tr -d ' ')
echo "Input log lines: $INPUT_COUNT"

# Count output events
OUTPUT_COUNT=$(wc -l < "$OUTPUT_FILE" | tr -d ' ')
echo "Output events:   $OUTPUT_COUNT"
echo ""

# --- Check 1: Event count ---
# Allow up to 3 drops (throttled microseg, dropped suricata notice, etc.)
# Also allow MORE events than input (MITM cloning produces extra microseg+fqdn events)
MIN_EXPECTED=$((INPUT_COUNT - 3))
echo "--- Event Count ---"
check "Output count ($OUTPUT_COUNT) >= minimum expected ($MIN_EXPECTED)" \
    "$([ "$OUTPUT_COUNT" -ge "$MIN_EXPECTED" ] && echo true || echo false)"

# --- Check 2: No grok parse failures ---
echo ""
echo "--- Parse Failures ---"
GROK_FAILURES=$(jq -r 'select(.tags[]? == "_grokparsefailure") | .message' "$OUTPUT_FILE" 2>/dev/null | head -5)
if [[ -z "$GROK_FAILURES" ]]; then
    check "No _grokparsefailure tags" "true"
else
    check "No _grokparsefailure tags" "false"
    echo "    Failed messages:"
    echo "$GROK_FAILURES" | while read -r line; do echo "      $line"; done
fi

# --- Check 3: Expected tags present ---
echo ""
echo "--- Tag Coverage ---"
EXPECTED_TAGS="microseg suricata mitm fqdn cmd gw_net_stats gw_sys_stats tunnel_status vpn_session"
for tag in $EXPECTED_TAGS; do
    TAG_COUNT=$(jq -r "select(.tags[]? == \"$tag\") | .tags" "$OUTPUT_FILE" 2>/dev/null | wc -l | tr -d ' ')
    check "Tag '$tag' present (count: $TAG_COUNT)" \
        "$([ "$TAG_COUNT" -gt 0 ] && echo true || echo false)"
done

# --- Check 4: @timestamp present on all events ---
echo ""
echo "--- Field Presence ---"
MISSING_TS=$(jq -r 'select(.["@timestamp"] == null) | .tags' "$OUTPUT_FILE" 2>/dev/null | wc -l | tr -d ' ')
check "@timestamp present on all events (missing: $MISSING_TS)" \
    "$([ "$MISSING_TS" -eq 0 ] && echo true || echo false)"

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
