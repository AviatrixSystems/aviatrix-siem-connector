#!/usr/bin/env python3
"""
Syslog Log Streamer - Stream test logs to a syslog endpoint for testing Logstash pipelines.

Usage:
    ./stream-logs.py                          # Stream all samples once to localhost:5000
    ./stream-logs.py --delay 0.5              # 500ms between messages
    ./stream-logs.py --filter microseg        # Only microseg logs
    ./stream-logs.py --loop                   # Continuous replay
    ./stream-logs.py --target 192.168.1.10    # Custom Logstash host
    ./stream-logs.py --port 514               # Custom port
    ./stream-logs.py --tcp                    # Use TCP instead of UDP
"""

import argparse
import socket
import sys
import time
import re
from pathlib import Path

# Log type patterns for filtering
LOG_TYPE_PATTERNS = {
    "microseg": r"AviatrixGwMicrosegPacket",
    "suricata": r'"event_type"\s*:\s*"alert"',
    "mitm": r"traffic_server\[",
    "cmd": r"AviatrixCMD|AviatrixAPI",
    "fqdn": r"AviatrixFQDNRule",
    "netstats": r"AviatrixGwNetStats",
    "sysstats": r"AviatrixGwSysStats",
    "tunnel": r"AviatrixTunnelStatusChange",
}

DEFAULT_LOG_FILE = Path(__file__).parent / "test-samples.log"


def load_logs(filepath: Path, filter_type: str = None) -> list[str]:
    """Load log lines from file, optionally filtering by type."""
    if not filepath.exists():
        print(f"Error: Log file not found: {filepath}", file=sys.stderr)
        sys.exit(1)

    logs = []
    with open(filepath, "r") as f:
        for line in f:
            line = line.strip()
            # Skip empty lines and comments
            if not line or line.startswith("#"):
                continue

            # Apply filter if specified
            if filter_type:
                pattern = LOG_TYPE_PATTERNS.get(filter_type.lower())
                if pattern and not re.search(pattern, line):
                    continue

            logs.append(line)

    return logs


def send_udp(sock: socket.socket, host: str, port: int, message: str):
    """Send message via UDP."""
    sock.sendto(message.encode("utf-8"), (host, port))


def send_tcp(sock: socket.socket, message: str):
    """Send message via TCP with newline delimiter."""
    sock.sendall((message + "\n").encode("utf-8"))


def stream_logs(
    logs: list[str],
    host: str,
    port: int,
    delay: float,
    use_tcp: bool,
    loop: bool,
    verbose: bool,
):
    """Stream logs to the target endpoint."""
    if use_tcp:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            sock.connect((host, port))
            print(f"Connected to {host}:{port} (TCP)")
        except ConnectionRefusedError:
            print(f"Error: Connection refused to {host}:{port}", file=sys.stderr)
            sys.exit(1)
        send_func = lambda msg: send_tcp(sock, msg)
    else:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        print(f"Sending to {host}:{port} (UDP)")
        send_func = lambda msg: send_udp(sock, host, port, msg)

    try:
        iteration = 0
        while True:
            iteration += 1
            if loop:
                print(f"\n--- Iteration {iteration} ---")

            for i, log in enumerate(logs, 1):
                if verbose:
                    # Truncate long lines for display
                    display = log[:100] + "..." if len(log) > 100 else log
                    print(f"[{i}/{len(logs)}] {display}")
                else:
                    print(f"\rSent {i}/{len(logs)} logs", end="", flush=True)

                send_func(log)

                if delay > 0 and i < len(logs):
                    time.sleep(delay)

            print(f"\nSent {len(logs)} log(s) to {host}:{port}")

            if not loop:
                break

            if delay > 0:
                print(f"Waiting {delay}s before next iteration...")
                time.sleep(delay)

    except KeyboardInterrupt:
        print("\nInterrupted by user")
    finally:
        sock.close()


def main():
    parser = argparse.ArgumentParser(
        description="Stream test logs to a syslog endpoint",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Log type filters:
  microseg   - AviatrixGwMicrosegPacket (L4 microsegmentation)
  suricata   - Suricata IDS/IPS alerts
  mitm       - traffic_server L7/TLS inspection
  cmd        - AviatrixCMD/API controller commands
  fqdn       - AviatrixFQDNRule firewall rules
  netstats   - AviatrixGwNetStats gateway network stats
  sysstats   - AviatrixGwSysStats gateway system stats
  tunnel     - AviatrixTunnelStatusChange tunnel state

Examples:
  ./stream-logs.py                           # Stream all to localhost:5000 UDP
  ./stream-logs.py --filter microseg         # Only microseg logs
  ./stream-logs.py --target 10.0.0.5 --tcp   # TCP to custom host
  ./stream-logs.py --loop --delay 1          # Continuous with 1s delay
""",
    )

    parser.add_argument(
        "-f", "--file",
        type=Path,
        default=DEFAULT_LOG_FILE,
        help=f"Log file to stream (default: {DEFAULT_LOG_FILE.name})",
    )
    parser.add_argument(
        "-t", "--target",
        default="localhost",
        help="Target host (default: localhost)",
    )
    parser.add_argument(
        "-p", "--port",
        type=int,
        default=5000,
        help="Target port (default: 5000)",
    )
    parser.add_argument(
        "--tcp",
        action="store_true",
        help="Use TCP instead of UDP",
    )
    parser.add_argument(
        "-d", "--delay",
        type=float,
        default=0.1,
        help="Delay between messages in seconds (default: 0.1)",
    )
    parser.add_argument(
        "--filter",
        choices=list(LOG_TYPE_PATTERNS.keys()),
        help="Filter logs by type",
    )
    parser.add_argument(
        "-l", "--loop",
        action="store_true",
        help="Continuously loop through logs",
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Show each log line as it's sent",
    )
    parser.add_argument(
        "--list-types",
        action="store_true",
        help="List available log types and exit",
    )

    args = parser.parse_args()

    if args.list_types:
        print("Available log type filters:")
        for name, pattern in LOG_TYPE_PATTERNS.items():
            print(f"  {name:12} - {pattern}")
        sys.exit(0)

    # Load and filter logs
    logs = load_logs(args.file, args.filter)

    if not logs:
        filter_msg = f" matching '{args.filter}'" if args.filter else ""
        print(f"No logs found{filter_msg} in {args.file}", file=sys.stderr)
        sys.exit(1)

    print(f"Loaded {len(logs)} log(s) from {args.file}")
    if args.filter:
        print(f"Filtered to: {args.filter}")

    # Stream logs
    stream_logs(
        logs=logs,
        host=args.target,
        port=args.port,
        delay=args.delay,
        use_tcp=args.tcp,
        loop=args.loop,
        verbose=args.verbose,
    )


if __name__ == "__main__":
    main()
