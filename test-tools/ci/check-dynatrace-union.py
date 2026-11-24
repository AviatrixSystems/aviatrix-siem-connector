#!/usr/bin/env python3
"""Check that outputs/dynatrace/output.conf is the union of its two fragments.

outputs/dynatrace/output.conf is kept in sync by hand with
outputs/dynatrace-metrics/output.conf and outputs/dynatrace-logs/output.conf:
all builder filters of metrics, then all builder filters of logs, then one
output block holding the metrics output body followed by the logs output body.

Comparison ignores blank lines, full-line comments and indentation, so the
combined file may keep its own header and section comments.

Usage: check-dynatrace-union.py [logstash-configs dir]
Exit code 0 when in sync, 1 when not (a unified diff is printed).
"""
import difflib
import os
import re
import sys

OUTPUT_START = re.compile(r"^output\s*\{\s*$")


def significant_lines(path):
    lines = []
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            lines.append(line)
    return lines


def split_sections(path):
    """Return (lines before the top-level output block, lines inside it)."""
    lines = significant_lines(path)
    starts = [i for i, line in enumerate(lines) if OUTPUT_START.match(line)]
    if len(starts) != 1:
        sys.exit(f"ERROR: expected exactly one top-level 'output {{' in {path}, found {len(starts)}")
    start = starts[0]
    if lines[-1] != "}":
        sys.exit(f"ERROR: {path} does not end with the closing brace of its output block")
    return lines[:start], lines[start + 1:-1]


def main():
    base = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "..", "logstash-configs")
    outputs = os.path.join(base, "outputs")
    combined = os.path.join(outputs, "dynatrace", "output.conf")
    metrics = os.path.join(outputs, "dynatrace-metrics", "output.conf")
    logs = os.path.join(outputs, "dynatrace-logs", "output.conf")

    c_pre, c_out = split_sections(combined)
    m_pre, m_out = split_sections(metrics)
    l_pre, l_out = split_sections(logs)

    ok = True
    for label, actual, expected in (
        ("builder filters", c_pre, m_pre + l_pre),
        ("output block", c_out, m_out + l_out),
    ):
        if actual != expected:
            ok = False
            print(f"FAIL: dynatrace/output.conf {label} differ from dynatrace-metrics + dynatrace-logs")
            sys.stdout.writelines(
                line + "\n"
                for line in difflib.unified_diff(
                    expected, actual,
                    fromfile="dynatrace-metrics + dynatrace-logs",
                    tofile="dynatrace/output.conf",
                    lineterm="", n=2))
        else:
            print(f"PASS: dynatrace/output.conf {label} match dynatrace-metrics + dynatrace-logs")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
