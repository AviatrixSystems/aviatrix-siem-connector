#!/bin/bash
# validate-output.sh - Validate Logstash E2E test output
# Usage: ./validate-output.sh <output.jsonl> <test-samples.log>
#
# Checks (all exact, so a regression that loses or duplicates one variant fails):
#   1. test-samples.log has EXPECTED_INPUT log lines (forces this file to be
#      updated together with the samples)
#   2. the output has exactly EXPECTED_TOTAL events
#   3. each log-type tag appears on exactly the expected number of events, and
#      every event carries exactly one log-type tag
#   4. no event carries 'unparsed' or any tag starting with '_' (grok, JSON,
#      date and Ruby failure tags: _avx_grok_failure_*, _avx_json_parse_failure,
#      _grokparsefailure, _jsonparsefailure, _dateparsefailure, _rubyexception)
#   5. every @timestamp is within MAX_TS_SKEW_SECONDS of now (default 7200;
#      0 disables). Run update-timestamps.py --overwrite before streaming.
#
# Expected counts for test-tools/sample-logs/test-samples.log: 54 lines in,
# 52 events out. The 2 dropped lines are the non-JSON suricata Notice and the
# suricata event_type=stats line. Nothing is throttled at this volume.
set -euo pipefail

OUTPUT_FILE="${1:?Usage: validate-output.sh <output.jsonl> <test-samples.log>}"
SAMPLE_FILE="${2:?Usage: validate-output.sh <output.jsonl> <test-samples.log>}"
MAX_TS_SKEW_SECONDS="${MAX_TS_SKEW_SECONDS:-7200}"

EXPECTED_INPUT=54
# tag:count, one entry per log type. Update together with test-samples.log.
EXPECTED_TAG_COUNTS="microseg:9 mitm:12 suricata:1 cmd:5 fqdn:3 gw_net_stats:7 gw_sys_stats:7 tunnel_status:4 vpn_session:4"

EXPECTED_TOTAL=0
TYPE_TAGS_JSON="["
for entry in $EXPECTED_TAG_COUNTS; do
    EXPECTED_TOTAL=$((EXPECTED_TOTAL + ${entry#*:}))
    TYPE_TAGS_JSON+="\"${entry%%:*}\","
done
TYPE_TAGS_JSON="${TYPE_TAGS_JSON%,}]"

PASS=0
FAIL=0

check() {
    local desc="$1"
    local result="$2"
    if [[ "$result" == "true" ]]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Logstash E2E Output Validation ==="
echo "Output file: $OUTPUT_FILE"
echo "Sample file: $SAMPLE_FILE"
echo ""

# Every output line must be valid JSON; otherwise the jq checks below lie.
if ! jq . "$OUTPUT_FILE" > /dev/null; then
    echo "FAIL: $OUTPUT_FILE is not valid JSON lines"
    exit 1
fi

# Count input lines (non-empty, non-comment)
INPUT_COUNT=$(grep -c '^[^#]' "$SAMPLE_FILE" | tr -d ' ')
echo "Input log lines: $INPUT_COUNT (expected $EXPECTED_INPUT)"

# Count output events
OUTPUT_COUNT=$(wc -l < "$OUTPUT_FILE" | tr -d ' ')
echo "Output events:   $OUTPUT_COUNT (expected $EXPECTED_TOTAL)"
echo ""

# --- Check 1/2: Event counts ---
echo "--- Event Count ---"
check "Sample file has $EXPECTED_INPUT log lines (found $INPUT_COUNT; update EXPECTED_* in this script with the samples)" \
    "$([ "$INPUT_COUNT" -eq "$EXPECTED_INPUT" ] && echo true || echo false)"
check "Output count ($OUTPUT_COUNT) == expected ($EXPECTED_TOTAL)" \
    "$([ "$OUTPUT_COUNT" -eq "$EXPECTED_TOTAL" ] && echo true || echo false)"

# --- Check 3: Per-tag counts ---
echo ""
echo "--- Tag Counts ---"
for entry in $EXPECTED_TAG_COUNTS; do
    tag="${entry%%:*}"
    want="${entry#*:}"
    got=$(jq -c --arg t "$tag" 'select((.tags // []) | index($t))' "$OUTPUT_FILE" | wc -l | tr -d ' ')
    check "Tag '$tag' count $got == $want" \
        "$([ "$got" -eq "$want" ] && echo true || echo false)"
done
NOT_ONE_TYPE=$(jq -c --argjson types "$TYPE_TAGS_JSON" \
    'select([(.tags // [])[] | select(. as $t | $types | index($t))] | length != 1) | .tags' \
    "$OUTPUT_FILE" | wc -l | tr -d ' ')
check "Every event has exactly one log-type tag (violations: $NOT_ONE_TYPE)" \
    "$([ "$NOT_ONE_TYPE" -eq 0 ] && echo true || echo false)"

# --- Check 4: No failure / unparsed tags ---
echo ""
echo "--- Parse Failures ---"
FAILED=$(jq -c 'select((.tags // []) | any(. == "unparsed" or startswith("_"))) | {tags, message}' "$OUTPUT_FILE")
if [[ -z "$FAILED" ]]; then
    check "No 'unparsed' or '_*' failure tags" "true"
else
    check "No 'unparsed' or '_*' failure tags ($(echo "$FAILED" | wc -l | tr -d ' ') events)" "false"
    echo "    First failing events:"
    echo "$FAILED" | head -5 | while read -r line; do echo "      ${line:0:400}"; done
fi

# --- Check 5: @timestamp parsed into the refreshed sample window ---
echo ""
echo "--- Timestamps ---"
if [[ "$MAX_TS_SKEW_SECONDS" -gt 0 ]]; then
    NOW=$(date -u +%s)
    BAD_TS=$(jq -c --argjson now "$NOW" --argjson max "$MAX_TS_SKEW_SECONDS" '
        select(
          (.["@timestamp"] // "" | tostring | sub("\\.[0-9]+Z$"; "Z") | try fromdateiso8601 catch null) as $ts
          | $ts == null or ($ts - $now | fabs) > $max
        ) | {"@timestamp": .["@timestamp"], tags}' "$OUTPUT_FILE")
    if [[ -z "$BAD_TS" ]]; then
        check "@timestamp within ${MAX_TS_SKEW_SECONDS}s of now on all events" "true"
    else
        check "@timestamp within ${MAX_TS_SKEW_SECONDS}s of now on all events ($(echo "$BAD_TS" | wc -l | tr -d ' ') off; refresh sample timestamps or set MAX_TS_SKEW_SECONDS=0)" "false"
        echo "$BAD_TS" | head -5 | while read -r line; do echo "      $line"; done
    fi
else
    echo "  SKIP: timestamp window check (MAX_TS_SKEW_SECONDS=0)"
fi

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
