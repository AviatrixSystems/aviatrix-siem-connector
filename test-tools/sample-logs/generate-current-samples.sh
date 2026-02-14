#!/bin/bash
# Generates test-samples.log with timestamps shifted to a recent window around now.
# Reads test-samples.log, replaces ALL timestamp formats in-place, writes to stdout.
#
# Usage:
#   ./generate-current-samples.sh                 # print to stdout
#   ./generate-current-samples.sh --overwrite      # overwrite test-samples.log in place
#   ./generate-current-samples.sh -o out.log       # write to specific file

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec python3 "${SCRIPT_DIR}/update-timestamps.py" "$@"
