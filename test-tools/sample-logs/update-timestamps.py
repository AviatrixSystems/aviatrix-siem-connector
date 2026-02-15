#!/usr/bin/env python3
"""
Rewrite all timestamps in test-samples.log to a random window around now.

Each log line gets a random time within the last WINDOW_SECONDS (default 300).
All timestamps within a single line are set to the same base time (with minor
offsets where the original had them, e.g. cpu_cores start/end 40s apart).

Handles every timestamp format in the sample file:
  1. Syslog:       "Feb 13 16:05:55" / "Dec  9 00:37:28"
  2. Internal:      "2026/02/13 16:05:55"
  3. ISO field:     "timestamp=2026-02-13T16:19:25.107597"
  4. Suricata JSON: "timestamp":"2025-12-09T00:37:28.699696+0000"
  5. Flow start:    "start":"2025-12-09T00:37:28.649344+0000"
  6. JSON epoch:    "timestamp":1765240615
  7. session_start: "session_start":1765240615296592159  (nanoseconds)
  8. cpu_cores:     seconds:1765240053 ... seconds:1765240093  (start/end pairs)
  9. CMD dual:      "Dec  9 00:45:08 1.2.3.4 Dec  9 00:45:07"
 10. ISO syslog:    2026-02-14T21:16:45.718808+00:00  (tunnel status, RFC 5424)
"""

import argparse
import os
import random
import re
import sys
import time
from datetime import datetime, timezone

WINDOW_SECONDS = 300  # spread log lines across last 5 minutes


def syslog_fmt(dt: datetime) -> str:
    """Format as syslog timestamp: 'Feb 14 09:32:05' (space-padded day)."""
    return dt.strftime("%b %e %H:%M:%S")


def slash_fmt(dt: datetime) -> str:
    """Format as '2026/02/14 09:32:05'."""
    return dt.strftime("%Y/%m/%d %H:%M:%S")


def iso_fmt(dt: datetime) -> str:
    """Format as '2026-02-14T09:32:05.107597'."""
    return dt.strftime("%Y-%m-%dT%H:%M:%S.") + f"{random.randint(100000, 999999)}"


def suricata_iso_fmt(dt: datetime) -> str:
    """Format as '2026-02-14T09:32:05.699696+0000'."""
    return dt.strftime("%Y-%m-%dT%H:%M:%S.") + f"{random.randint(100000, 999999)}+0000"


def iso_syslog_fmt(dt: datetime) -> str:
    """Format as '2026-02-14T09:32:05.718808+00:00' (RFC 5424 syslog)."""
    return dt.strftime("%Y-%m-%dT%H:%M:%S.") + f"{random.randint(100000, 999999)}+00:00"


def rewrite_line(line: str, base_epoch: int) -> str:
    """Replace all timestamps in a single log line with times based on base_epoch."""
    dt = datetime.fromtimestamp(base_epoch, tz=timezone.utc)

    # For cpu_cores: start = base - 40s, end = base (matching original ~40s window)
    core_start = base_epoch - 40
    core_end = base_epoch

    # --- 1. Syslog timestamps: "Mon DD HH:MM:SS" or "Mon  D HH:MM:SS" ---
    # These appear at the start of lines and in CMD logs (which have two)
    syslog_pat = re.compile(
        r"(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)"
        r"([ ]\d{2}|[ ][ ]\d)"
        r" (\d{2}:\d{2}:\d{2})"
    )
    line = syslog_pat.sub(syslog_fmt(dt), line)

    # --- 1b. ISO8601 syslog timestamps: "YYYY-MM-DDTHH:MM:SS.ffffff+HH:MM" ---
    # Used by tunnel_status logs (RFC 5424 format with colon in tz offset).
    # Must run before patterns 3/4 which match different ISO8601 variants.
    line = re.sub(
        r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+\+\d{2}:\d{2}",
        iso_syslog_fmt(dt),
        line,
    )

    # --- 2. Internal slash format: "YYYY/MM/DD HH:MM:SS" ---
    line = re.sub(r"\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}", slash_fmt(dt), line)

    # --- 3. ISO timestamp field: "timestamp=YYYY-MM-DDTHH:MM:SS.ffffff" ---
    line = re.sub(
        r"(timestamp=)\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+",
        lambda m: m.group(1) + iso_fmt(dt),
        line,
    )

    # --- 4. Suricata JSON timestamp: "timestamp":"..." ---
    line = re.sub(
        r'("timestamp":")(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+\+\d{4})(")',
        lambda m: m.group(1) + suricata_iso_fmt(dt) + m.group(3),
        line,
    )

    # --- 5. Flow start: "start":"..." ---
    line = re.sub(
        r'("start":")(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+\+\d{4})(")',
        lambda m: m.group(1) + suricata_iso_fmt(dt) + m.group(3),
        line,
    )

    # --- 6. JSON unix epoch: "timestamp":NNNNNNNNNN ---
    line = re.sub(
        r'("timestamp":)\d{10}',
        lambda m: m.group(1) + str(base_epoch),
        line,
    )

    # --- 7. session_start nanoseconds: "session_start":NNNN...NNN ---
    nano_epoch = base_epoch * 1_000_000_000 + random.randint(100_000_000, 999_999_999)
    line = re.sub(
        r'("session_start":)\d{16,}',
        lambda m: m.group(1) + str(nano_epoch),
        line,
    )

    # --- 8. cpu_cores protobuf seconds ---
    # Pattern: pairs of start/end with ~40s gap. Replace all occurrences.
    # Find unique epoch values in seconds:N fields and build a mapping.
    seen_seconds = {}

    def replace_seconds(m):
        old_val = int(m.group(1))
        if old_val not in seen_seconds:
            # First unique value gets core_start, second gets core_end, etc.
            if len(seen_seconds) == 0:
                seen_seconds[old_val] = core_start
            elif len(seen_seconds) == 1:
                # If this value is bigger than the first, it's the end
                first_old = list(seen_seconds.keys())[0]
                if old_val > first_old:
                    seen_seconds[old_val] = core_end
                else:
                    seen_seconds[old_val] = core_start
            else:
                seen_seconds[old_val] = core_end
        return f"seconds:{seen_seconds[old_val]}"

    line = re.sub(r"seconds:(\d{10})", replace_seconds, line)

    # --- 9. cpu_cores nanos (keep as random realistic values) ---
    line = re.sub(
        r"nanos:\d+",
        lambda m: f"nanos:{random.randint(10_000_000, 999_999_999)}",
        line,
    )

    return line


def main():
    parser = argparse.ArgumentParser(
        description="Rewrite timestamps in test-samples.log to current time window"
    )
    parser.add_argument(
        "-o", "--output", help="Write to this file instead of stdout"
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite test-samples.log in place",
    )
    parser.add_argument(
        "-w",
        "--window",
        type=int,
        default=WINDOW_SECONDS,
        help=f"Spread timestamps over last N seconds (default: {WINDOW_SECONDS})",
    )
    parser.add_argument(
        "-i",
        "--input",
        help="Input file (default: test-samples.log in same directory)",
    )
    args = parser.parse_args()

    script_dir = os.path.dirname(os.path.abspath(__file__))
    input_path = args.input or os.path.join(script_dir, "test-samples.log")

    with open(input_path, "r") as f:
        lines = f.readlines()

    now = int(time.time())
    output_lines = []
    log_line_index = 0

    # Count actual log lines (non-comment, non-blank) for even time distribution
    log_lines = [
        i
        for i, l in enumerate(lines)
        if l.strip() and not l.strip().startswith("#")
    ]
    num_log_lines = len(log_lines)

    for i, line in enumerate(lines):
        stripped = line.strip()

        # Pass through comments, blank lines, and section headers unchanged
        if not stripped or stripped.startswith("#"):
            output_lines.append(line)
            continue

        # Assign a time: spread log lines evenly across the window, with jitter
        if num_log_lines > 1:
            position = log_line_index / (num_log_lines - 1)
        else:
            position = 0.5
        # Base time spreads from (now - window) to (now - 10s), with ±5s jitter
        base_time = int(
            now - args.window + (position * (args.window - 10))
        )
        base_time += random.randint(-5, 5)
        base_time = min(base_time, now - 2)  # always at least 2s in the past

        output_lines.append(rewrite_line(line, base_time))
        log_line_index += 1

    result = "".join(output_lines)

    if args.overwrite:
        with open(input_path, "w") as f:
            f.write(result)
        print(
            f"Updated {num_log_lines} log lines in {input_path}",
            file=sys.stderr,
        )
    elif args.output:
        with open(args.output, "w") as f:
            f.write(result)
        print(
            f"Wrote {num_log_lines} log lines to {args.output}",
            file=sys.stderr,
        )
    else:
        sys.stdout.write(result)


if __name__ == "__main__":
    main()
