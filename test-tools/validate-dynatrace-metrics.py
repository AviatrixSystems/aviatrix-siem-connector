#!/usr/bin/env python3
"""Validate Dynatrace MINT line protocol output.

Reads MINT lines from file(s) or stdin, validates each line against the
Dynatrace metric ingestion protocol spec, and reports errors.

Usage:
    # Validate a file
    ./validate-dynatrace-metrics.py captured-output.txt

    # Pipe from webhook viewer capture
    cat payload.txt | ./validate-dynatrace-metrics.py

    # Check that all expected metrics appear for each gateway
    ./validate-dynatrace-metrics.py --check-completeness captured-output.txt

    # Verbose: show each line and its parse result
    ./validate-dynatrace-metrics.py -v captured-output.txt
"""

import argparse
import re
import sys
import time

# MINT metric key: 3-255 chars, a-zA-Z0-9._- , cannot start with dt., number, or hyphen
METRIC_KEY_RE = re.compile(
    r'^[a-zA-Z_][a-zA-Z0-9._-]{2,254}$'
)

# Dimension key: lowercase letters, numbers, -, ., :, _ — max 100 chars
DIM_KEY_RE = re.compile(r'^[a-z0-9_.\-:]{1,100}$')

# Payload patterns
GAUGE_RE = re.compile(
    r'^gauge,'
    r'(?:min=[\d.eE+-]+,max=[\d.eE+-]+,sum=[\d.eE+-]+,count=\d+'  # pre-aggregated
    r'|[\d.eE+-]+)$'  # simple value
)
COUNT_RE = re.compile(r'^count,delta=[\d.eE+-]+$')

# Timestamp: UTC milliseconds
TS_RE = re.compile(r'^\d{13}$')

# Expected sys_stats metrics (without per-core)
EXPECTED_SYS_STATS = {
    'aviatrix.gateway.cpu.idle',
    'aviatrix.gateway.cpu.usage',
    'aviatrix.gateway.memory.avail',
    'aviatrix.gateway.memory.total',
    'aviatrix.gateway.memory.free',
    'aviatrix.gateway.memory.used',
    'aviatrix.gateway.memory.usage',
    'aviatrix.gateway.disk.avail',
    'aviatrix.gateway.disk.total',
    'aviatrix.gateway.disk.used',
    'aviatrix.gateway.disk.used.percent',
}

# Expected net_stats metrics (gauge)
EXPECTED_NET_STATS_GAUGE = {
    'aviatrix.gateway.net.bytes_rx',
    'aviatrix.gateway.net.bytes_tx',
    'aviatrix.gateway.net.bytes_total_rate',
    'aviatrix.gateway.net.rx_cumulative',
    'aviatrix.gateway.net.tx_cumulative',
    'aviatrix.gateway.net.rx_tx_cumulative',
}

# Optional net_stats gauge metrics (may not be present on all gateways)
OPTIONAL_NET_STATS_GAUGE = {
    'aviatrix.gateway.net.conntrack.count',
    'aviatrix.gateway.net.conntrack.avail',
    'aviatrix.gateway.net.conntrack.usage',
}

# Expected net_stats count metrics (optional — may be 0 and still present)
EXPECTED_NET_STATS_COUNT = {
    'aviatrix.gateway.net.conntrack_limit_exceeded',
    'aviatrix.gateway.net.bw_in_limit_exceeded',
    'aviatrix.gateway.net.bw_out_limit_exceeded',
    'aviatrix.gateway.net.pps_limit_exceeded',
    'aviatrix.gateway.net.linklocal_limit_exceeded',
}


def parse_dimensions(dim_str):
    """Parse comma-separated dimension string, handling quoted values."""
    dims = {}
    errors = []
    i = 0
    while i < len(dim_str):
        # Find key
        eq_pos = dim_str.find('=', i)
        if eq_pos == -1:
            errors.append(f"Missing '=' in dimension at pos {i}")
            break
        key = dim_str[i:eq_pos]

        if not DIM_KEY_RE.match(key):
            errors.append(f"Invalid dimension key: '{key}'")

        # Parse value (quoted or unquoted)
        val_start = eq_pos + 1
        if val_start < len(dim_str) and dim_str[val_start] == '"':
            # Quoted value — find closing quote (handling escapes)
            j = val_start + 1
            while j < len(dim_str):
                if dim_str[j] == '\\':
                    j += 2
                    continue
                if dim_str[j] == '"':
                    break
                j += 1
            value = dim_str[val_start + 1:j]
            if len(value) > 250:
                errors.append(f"Dimension value too long ({len(value)} > 250): '{key}'")
            dims[key] = value
            i = j + 1
            if i < len(dim_str) and dim_str[i] == ',':
                i += 1
        else:
            # Unquoted value — find next comma
            comma_pos = dim_str.find(',', val_start)
            if comma_pos == -1:
                value = dim_str[val_start:]
                i = len(dim_str)
            else:
                value = dim_str[val_start:comma_pos]
                i = comma_pos + 1
            dims[key] = value

    return dims, errors


def validate_line(line, line_num, now_ms):
    """Validate a single MINT line. Returns (is_valid, metric_key, dims, errors)."""
    errors = []

    # Skip empty lines and metadata/comment lines
    stripped = line.strip()
    if not stripped or stripped.startswith('#'):
        return True, None, {}, []

    # Split into parts: metric_key_and_dims SPACE payload [SPACE timestamp]
    parts = stripped.split(' ')
    if len(parts) < 2 or len(parts) > 3:
        return False, None, {}, [f"Line {line_num}: Expected 2-3 space-separated parts, got {len(parts)}"]

    key_dims = parts[0]
    payload = parts[1]
    timestamp = parts[2] if len(parts) == 3 else None

    # Split metric key from dimensions at first comma
    first_comma = key_dims.find(',')
    if first_comma == -1:
        metric_key = key_dims
        dim_str = ''
    else:
        metric_key = key_dims[:first_comma]
        dim_str = key_dims[first_comma + 1:]

    # Validate metric key
    if not METRIC_KEY_RE.match(metric_key):
        if len(metric_key) < 3:
            errors.append(f"Line {line_num}: Metric key too short ({len(metric_key)} < 3): '{metric_key}'")
        elif len(metric_key) > 255:
            errors.append(f"Line {line_num}: Metric key too long ({len(metric_key)} > 255): '{metric_key}'")
        else:
            errors.append(f"Line {line_num}: Invalid metric key format: '{metric_key}'")

    if metric_key.startswith('dt.'):
        errors.append(f"Line {line_num}: Metric key cannot start with 'dt.': '{metric_key}'")

    # Validate dimensions
    dims = {}
    if dim_str:
        dims, dim_errors = parse_dimensions(dim_str)
        for e in dim_errors:
            errors.append(f"Line {line_num}: {e}")
        if len(dims) > 50:
            errors.append(f"Line {line_num}: Too many dimensions ({len(dims)} > 50)")

    # Validate payload
    if not GAUGE_RE.match(payload) and not COUNT_RE.match(payload):
        # Try bare numeric (implicit gauge)
        try:
            float(payload)
        except ValueError:
            errors.append(f"Line {line_num}: Invalid payload format: '{payload}'")

    # Validate timestamp
    if timestamp:
        if not TS_RE.match(timestamp):
            errors.append(f"Line {line_num}: Invalid timestamp format (expected 13-digit ms): '{timestamp}'")
        elif now_ms:
            ts_val = int(timestamp)
            one_hour_ago = now_ms - 3600000
            ten_min_future = now_ms + 600000
            if ts_val < one_hour_ago or ts_val > ten_min_future:
                errors.append(
                    f"Line {line_num}: Timestamp out of range "
                    f"(must be within -1h/+10m of now): {timestamp}"
                )

    is_valid = len(errors) == 0
    return is_valid, metric_key, dims, errors


def check_completeness(all_metrics):
    """Check that expected metric sets appear for each gateway."""
    # Group by gateway
    gateways = {}
    for metric_key, dims in all_metrics:
        gw = dims.get('gateway', 'unknown')
        if gw not in gateways:
            gateways[gw] = set()
        gateways[gw].add(metric_key)

    issues = []
    for gw, keys in sorted(gateways.items()):
        # Check if this looks like sys_stats or net_stats
        has_cpu = any(k.startswith('aviatrix.gateway.cpu') for k in keys)
        has_net = any(k.startswith('aviatrix.gateway.net') for k in keys)

        if has_cpu:
            missing = EXPECTED_SYS_STATS - keys
            if missing:
                issues.append(f"  Gateway '{gw}' missing sys_stats metrics: {sorted(missing)}")

        if has_net:
            missing = EXPECTED_NET_STATS_GAUGE - keys
            if missing:
                issues.append(f"  Gateway '{gw}' missing net_stats gauge metrics: {sorted(missing)}")

    return issues


def main():
    parser = argparse.ArgumentParser(
        description='Validate Dynatrace MINT line protocol output'
    )
    parser.add_argument(
        'files', nargs='*', default=['-'],
        help='Files to validate (default: stdin)'
    )
    parser.add_argument(
        '-v', '--verbose', action='store_true',
        help='Show each line and its parse result'
    )
    parser.add_argument(
        '--check-completeness', action='store_true',
        help='Verify all expected metrics appear for each gateway'
    )
    parser.add_argument(
        '--no-timestamp-check', action='store_true',
        help='Skip timestamp range validation'
    )
    args = parser.parse_args()

    now_ms = int(time.time() * 1000)
    if args.no_timestamp_check:
        now_ms = None

    total_lines = 0
    valid_count = 0
    invalid_count = 0
    skipped_count = 0
    all_errors = []
    metric_key_counts = {}
    all_metrics = []  # (metric_key, dims) for completeness check

    for filepath in args.files:
        if filepath == '-':
            source = sys.stdin
            source_name = '<stdin>'
        else:
            try:
                source = open(filepath, 'r')
            except FileNotFoundError:
                print(f"Error: File not found: {filepath}", file=sys.stderr)
                sys.exit(1)
            source_name = filepath

        for line_num, line in enumerate(source, 1):
            line = line.rstrip('\n\r')
            if not line.strip() or line.strip().startswith('#'):
                skipped_count += 1
                continue

            total_lines += 1
            is_valid, metric_key, dims, errors = validate_line(line, line_num, now_ms)

            if is_valid:
                valid_count += 1
                if metric_key:
                    metric_key_counts[metric_key] = metric_key_counts.get(metric_key, 0) + 1
                    all_metrics.append((metric_key, dims))
            else:
                invalid_count += 1
                all_errors.extend(errors)

            if args.verbose:
                status = "OK" if is_valid else "INVALID"
                print(f"[{status}] L{line_num}: {line[:120]}")
                if errors:
                    for e in errors:
                        print(f"         {e}")

        if filepath != '-' and source != sys.stdin:
            source.close()

    # Summary
    print(f"\n{'='*60}")
    print(f"MINT Validation Summary")
    print(f"{'='*60}")
    print(f"Total data lines:  {total_lines}")
    print(f"Valid:             {valid_count}")
    print(f"Invalid:           {invalid_count}")
    print(f"Skipped (empty/#): {skipped_count}")
    print()

    if metric_key_counts:
        print("Metric keys found:")
        for key in sorted(metric_key_counts.keys()):
            print(f"  {key}: {metric_key_counts[key]}")
        print()

    if all_errors:
        print("Errors:")
        for e in all_errors:
            print(f"  {e}")
        print()

    if args.check_completeness:
        issues = check_completeness(all_metrics)
        if issues:
            print("Completeness issues:")
            for issue in issues:
                print(issue)
            print()
        else:
            print("Completeness: All expected metrics present for all gateways.")
            print()

    sys.exit(1 if invalid_count > 0 else 0)


if __name__ == '__main__':
    main()
