#!/usr/bin/env python3
"""Golden input/output tests for the SIEM connector.

Every sample line in the corpus (test-tools/sample-logs/*.log) carries a
`# @case <id>` annotation. For each output type this tool runs the engine in a
container, sends the cases one at a time over TCP syslog, records every HTTP
request the engine makes (a local capture server stands in for Splunk HEC,
Dynatrace and Azure) and writes, per case, the normalized requests to
test-tools/golden/expected/<output>/<case-id>.json.

  generate   run the engine and (re)write the expected files
  check      run the engine and diff against the expected files (exit 1 on any
             difference); this is the red/green loop for porting work

Outputs:
  parsed               every event after the filter stage (whole event as JSON)
  splunk-hec           exact HEC request bodies
  dynatrace-logs       exact Dynatrace log ingest bodies
  azure-log-ingestion  the record sent per DCR stream (the Sentinel plugin is
                       swapped for an http output, since it needs real Entra ID)

Engines: logstash (today). A fluentbit engine only needs a config builder and
the same environment contract (see README.md).

Case/output correlation is deterministic: after each case a "barrier" tunnel
status line is sent. The pipeline runs with one worker (ordered), so once the
barrier event reaches the capture server, everything the case produced has
been sent. Nothing depends on sleep timing except a short grace period for
requests issued concurrently within one output batch.

Stdlib only (Python 3.9+). Requires docker.
"""

from __future__ import annotations

import argparse
import difflib
import gzip
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GOLDEN_DIR = ROOT / "test-tools" / "golden"
EXPECTED_DIR = GOLDEN_DIR / "expected"
CONFIG_DIR = ROOT / "logstash-configs"
DEFAULT_CORPUS = [
    ROOT / "test-tools" / "sample-logs" / "test-samples.log",
    ROOT / "test-tools" / "sample-logs" / "edge-cases.log",
]
LOGSTASH_IMAGE = os.environ.get("LOGSTASH_IMAGE", "docker.elastic.co/logstash/logstash:8.16.2")
OUTPUTS = ["parsed", "splunk-hec", "dynatrace-logs", "azure-log-ingestion"]

BARRIER_MARK = "golden-barrier-"
BARRIER_TEMPLATE = (
    "<14>2026-01-01T00:00:00.000000+00:00 golden-host cloudxd: AviatrixTunnelStatusChange: "
    "src_gw=" + BARRIER_MARK + "{n}(NA NA) dst_gw=golden-peer(NA NA) old_state=Up new_state=Down"
)
GRACE_SECONDS = 0.4
BARRIER_TIMEOUT = 120.0  # http outputs retry with backoff after a transient failure
STARTUP_TIMEOUT = 240.0

# Keys whose values are time-derived. Syslog headers without a year are parsed
# into the current year, so years are masked for these keys (and for any string
# that is entirely an ISO-8601 timestamp). Month/day/time must still match.
TIME_KEYS = {
    "@timestamp", "timestamp", "time", "unix_time", "TimeGenerated",
    "EventStartTime", "EventEndTime",
}
# Keys dropped before comparison: engine bookkeeping, not part of the contract.
IGNORE_KEYS = {"@version"}
# Input-connection metadata that differs per run (sender address and port).
IGNORE_PATHS = {("host",), ("port",)}

ISO_RE = re.compile(r"^(\d{4})(-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?)$")


# --------------------------------------------------------------------------- corpus

@dataclass
class Case:
    id: str
    line: str
    source: str  # file:lineno (for messages only; not stored, it churns)
    avx_min: str = ""    # first Aviatrix release that emits this line ("" = unversioned)
    avx_until: str = ""  # last release that emits it ("" = still current)


def version_key(v: str) -> tuple:
    return tuple(int(x) for x in re.findall(r"\d+", v)) if v else ()


def applies_to(case: Case, release: str) -> bool:
    """True if `release` emits the case. `avx=9.0` starts at 9.0.0; `until=10.0`
    covers every 10.0.x; a bare `--avx 9` means 9.0.0."""
    r = version_key(release)
    if case.avx_min:
        lo = version_key(case.avx_min)
        width = max(len(lo), len(r))
        if r + (0,) * (width - len(r)) < lo + (0,) * (width - len(lo)):
            return False
    if case.avx_until:
        hi = version_key(case.avx_until)
        if r[:len(hi)] > hi:
            return False
    return True


def load_corpus(paths: list[Path]) -> list[Case]:
    cases: list[Case] = []
    seen: dict[str, str] = {}
    errors: list[str] = []
    for path in paths:
        if not path.exists():
            continue
        pending: tuple[str, str, str] | None = None  # (id, avx, until)
        for lineno, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            line = raw.strip()
            m = re.match(r"^#\s*@case\s+([a-z0-9][a-z0-9._-]*)((?:\s+[a-z]+=\S+)*)\s*$", line)
            if m:
                if pending:
                    errors.append(f"{path.name}:{lineno}: @case {pending[0]} has no sample line")
                attrs = dict(a.split("=", 1) for a in m.group(2).split())
                unknown = set(attrs) - {"avx", "until"}
                if unknown:
                    errors.append(f"{path.name}:{lineno}: unknown @case attribute(s) {sorted(unknown)}")
                pending = (m.group(1), attrs.get("avx", ""), attrs.get("until", ""))
                continue
            if re.match(r"^#\s*@case\b", line):
                errors.append(f"{path.name}:{lineno}: malformed @case annotation: {line}")
                continue
            if not line or line.startswith("#"):
                continue
            where = f"{path.relative_to(ROOT)}:{lineno}"
            if not pending:
                errors.append(f"{where}: sample line without a preceding '# @case <id>'")
                continue
            cid, avx_min, avx_until = pending
            if cid in seen:
                errors.append(f"{where}: duplicate case id {cid} (first at {seen[cid]})")
            seen[cid] = where
            cases.append(Case(cid, raw.rstrip("\r\n"), where, avx_min, avx_until))
            pending = None
        if pending:
            errors.append(f"{path.name}: trailing @case {pending[0]} has no sample line")
    if errors:
        sys.exit("corpus errors:\n  " + "\n  ".join(errors))
    return cases


# --------------------------------------------------------------------------- capture server

class Capture:
    def __init__(self) -> None:
        self.lock = threading.Condition()
        self.requests: list[dict] = []
        self.barriers: set[int] = set()

    def add(self, req: dict) -> None:
        with self.lock:
            self.requests.append(req)
            for ev in req["events"]:
                n = barrier_number(ev)
                if n is not None:
                    self.barriers.add(n)
            self.lock.notify_all()

    def wait_barrier(self, n: int, timeout: float) -> bool:
        deadline = time.monotonic() + timeout
        with self.lock:
            while n not in self.barriers:
                left = deadline - time.monotonic()
                if left <= 0:
                    return False
                self.lock.wait(left)
            return True

    def drain(self) -> list[dict]:
        with self.lock:
            out, self.requests = self.requests, []
            return out


def barrier_number(ev) -> int | None:
    s = ev if isinstance(ev, str) else json.dumps(ev)
    m = re.search(BARRIER_MARK + r"(\d+)", s)
    return int(m.group(1)) if m else None


def split_events(body: bytes) -> list:
    text = body.decode("utf-8", errors="replace").strip()
    if not text:
        return []
    try:
        val = json.loads(text)
        return val if isinstance(val, list) else [val]
    except json.JSONDecodeError:
        pass
    # Splunk HEC batches are concatenated JSON objects; also handles JSON lines.
    dec, i, out = json.JSONDecoder(), 0, []
    try:
        while i < len(text):
            while i < len(text) and text[i].isspace():
                i += 1
            if i >= len(text):
                break
            obj, i = dec.raw_decode(text, i)
            out.append(obj)
        return out
    except json.JSONDecodeError:
        return [text]  # non-JSON body (e.g. raw text); compare verbatim


def make_handler(capture: Capture):
    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):  # noqa: N802
            length = int(self.headers.get("Content-Length") or 0)
            body = self.rfile.read(length)
            if self.headers.get("Content-Encoding", "").lower() == "gzip":
                body = gzip.decompress(body)
            auth = self.headers.get("Authorization", "")
            capture.add({
                "path": self.path.split("?")[0],
                "content_type": (self.headers.get("Content-Type") or "").split(";")[0].strip(),
                "auth_scheme": auth.split(" ")[0] if auth else "",
                "events": split_events(body),
            })
            payload = b'{"text":"Success","code":0}'
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        do_PUT = do_POST  # noqa: N815

        def log_message(self, *args):  # silence
            pass

    return Handler


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


# --------------------------------------------------------------------------- engines

class LogstashEngine:
    """Runs the real assembled Logstash config with outputs pointed at the capture server."""

    def __init__(self, output: str, capture_port: int, workdir: Path, image: str):
        self.output, self.capture_port, self.workdir, self.image = output, capture_port, workdir, image
        self.name = f"golden-{output}-{os.getpid()}"
        self.send_port = free_port()

    def _assemble(self, output_type: str) -> str:
        dest = self.workdir / f"{output_type}-assembled.conf"
        subprocess.run([str(CONFIG_DIR / "scripts" / "assemble-config.sh"), output_type, str(dest)],
                       check=True, stdout=subprocess.DEVNULL)
        return dest.read_text()

    def build_config(self) -> str:
        cap = "${GOLDEN_CAPTURE_URL}"
        if self.output == "parsed":
            conf = self._assemble("ci-test")
            ci_out = (CONFIG_DIR / "outputs" / "ci-test" / "output.conf").read_text()
            body = ci_out[ci_out.index("output {"):]
            if body not in conf:
                sys.exit("could not locate the ci-test output block in the assembled config")
            return conf.replace(body, 'output {\n  http {\n    id => "golden-parsed"\n'
                                      '    http_method => "post"\n'
                                      f'    url => "{cap}/parsed"\n    format => "json"\n  }}\n}}\n')
        conf = self._assemble(self.output)
        if self.output == "azure-log-ingestion":
            pat = re.compile(r'microsoft-sentinel-log-analytics-logstash-output-plugin \{\s*'
                             r'id => "([^"]+)".*?\n\s+\}(?=[ \t]*\n)', re.S)  # body has ${VAR}s
            conf, n = pat.subn(lambda m: ('http {\n            id => "%s"\n'
                                          '            http_method => "post"\n'
                                          '            url => "%s/azure/%s"\n'
                                          '            format => "json"\n        }')
                               % (m.group(1), cap, m.group(1)), conf)
            if n != 8:
                sys.exit(f"expected to replace 8 Azure plugin blocks, replaced {n}")
        return conf

    def env(self) -> list[str]:
        out = subprocess.run([str(ROOT / "test-tools" / "ci" / "output-env-vars.sh"),
                              "ci-test" if self.output == "parsed" else self.output,
                              str(self.workdir / "golden.conf")],
                             check=True, capture_output=True, text=True).stdout.split()
        base = f"http://host.docker.internal:{self.capture_port}"
        overrides = {
            "GOLDEN_CAPTURE_URL": base,
            "LOG_PROFILE": "all",
            "SPLUNK_ADDRESS": "http://host.docker.internal",
            "SPLUNK_PORT": str(self.capture_port),
            "SPLUNK_HEC_AUTH": "golden-token",
            "SPLUNK_INCLUDE_SYSLOG": "true",
            "DT_LOGS_URL": f"{base}/dynatrace/logs",
            "DT_LOGS_TOKEN": "golden-token",
            "SYSLOG_TIMEZONE": "UTC",
            # Small heap: the corpus is tiny, and Podman/Docker VMs are often 2 GiB.
            "LS_JAVA_OPTS": os.environ.get("GOLDEN_LS_JAVA_OPTS", "-Xms512m -Xmx512m"),
        }
        env = {}
        for tok in out:
            if tok == "-e":
                continue
            k, _, v = tok.partition("=")
            env[k] = v
        env.update(overrides)
        flags = []
        for k, v in env.items():
            flags += ["-e", f"{k}={v}"]
        return flags

    def start(self) -> None:
        conf = self.build_config()
        (self.workdir / "golden.conf").write_text(conf)
        cmd = ["docker", "run", "-d", "--name", self.name,
               "--add-host", "host.docker.internal:host-gateway",
               "-p", f"127.0.0.1:{self.send_port}:5000/tcp",
               "-v", f"{self.workdir}:/config:ro",
               "-v", f"{CONFIG_DIR / 'patterns'}:/usr/share/logstash/patterns:ro",
               *self.env(), self.image,
               "logstash", "-f", "/config/golden.conf", "-w", "1",
               "--pipeline.batch.delay", "10"]
        subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL)

    def logs(self, tail: int = 80) -> str:
        r = subprocess.run(["docker", "logs", "--tail", str(tail), self.name],
                           capture_output=True, text=True)
        return r.stdout + r.stderr

    def running(self) -> bool:
        r = subprocess.run(["docker", "inspect", "-f", "{{.State.Running}}", self.name],
                           capture_output=True, text=True)
        return r.stdout.strip() == "true"

    def stop(self) -> None:
        subprocess.run(["docker", "rm", "-f", self.name], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)


ENGINES = {"logstash": LogstashEngine}


# --------------------------------------------------------------------------- normalization

RECEIVE_TIME = "<receive time>"
RECEIVE_WINDOW_SECONDS = 1800  # a timestamp this close to the run is the engine's clock


def _is_receive_time(dt: datetime) -> bool:
    return abs((dt - datetime.now(timezone.utc)).total_seconds()) < RECEIVE_WINDOW_SECONDS


def _parse_iso(v: str) -> datetime | None:
    m = re.match(r"^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}:\d{2})(?:\.(\d+))?(Z|[+-]\d{2}:?\d{2})?$", v)
    if not m:
        return None
    frac = (m.group(3) or "0")[:6].ljust(6, "0")
    tz = m.group(4) or "+00:00"
    tz = "+00:00" if tz == "Z" else (tz if ":" in tz else tz[:3] + ":" + tz[3:])
    try:
        return datetime.fromisoformat(f"{m.group(1)}T{m.group(2)}.{frac}{tz}")
    except ValueError:
        return None


def _mask_time(v):
    """Events whose source timestamp could not be parsed carry the engine's
    receive time; replace it with a placeholder. Otherwise mask only the year."""
    if isinstance(v, bool):
        return v
    if isinstance(v, (int, float)):
        secs = v / 1000.0 if v > 1e11 else float(v)  # epoch ms vs s
        dt = datetime.fromtimestamp(secs, tz=timezone.utc)
        if _is_receive_time(dt):
            return RECEIVE_TIME
        return "YYYY" + dt.strftime("-%m-%dT%H:%M:%S.%f")[:-3] + "Z (epoch)"
    if isinstance(v, str):
        m = ISO_RE.match(v)
        if m:
            dt = _parse_iso(v)
            if dt and _is_receive_time(dt):
                return RECEIVE_TIME
            return "YYYY" + m.group(2)
        try:
            return _mask_time(float(v))
        except ValueError:
            return v
    return v


def normalize(v, path: tuple = ()):
    if isinstance(v, dict):
        out = {}
        for k, val in v.items():
            p = path + (k,)
            if k in IGNORE_KEYS or p in IGNORE_PATHS:
                continue
            out[k] = _mask_time(val) if k in TIME_KEYS and not isinstance(val, (dict, list)) \
                else normalize(val, p)
        return out
    if isinstance(v, list):
        return [normalize(x, path) for x in v]
    if isinstance(v, float) and v.is_integer():
        return int(v)
    if isinstance(v, str):
        m = ISO_RE.match(v)
        if m:
            return _mask_time(v)
        # A JSON document embedded as a string (e.g. Splunk MITM "event"): its key
        # order is not stable, so compare it decoded, marked as a string.
        if v[:1] in "{[" and v[-1:] in "}]":
            try:
                return {"__json_string__": normalize(json.loads(v), path)}
            except json.JSONDecodeError:
                pass
        return v
    return v


def canon(v) -> str:
    return json.dumps(v, sort_keys=True, ensure_ascii=False)


def build_record(case: Case, requests: list[dict]) -> dict:
    reqs = []
    for r in requests:
        events = [normalize(e) for e in r["events"] if barrier_number(e) is None]
        if not events:
            continue
        reqs.append({"path": r["path"], "content_type": r["content_type"],
                     "auth_scheme": r["auth_scheme"], "events": sorted(events, key=canon)})
    reqs.sort(key=canon)
    rec = {"case": case.id, "input": case.line, "requests": reqs}
    if case.avx_min or case.avx_until:
        rec["avx"] = {k: v for k, v in (("min", case.avx_min), ("until", case.avx_until)) if v}
    return rec


def dumps(record: dict) -> str:
    return json.dumps(record, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


# --------------------------------------------------------------------------- run

def run_output(engine_name: str, output: str, cases: list[Case], image: str, verbose: bool) -> dict[str, dict]:
    capture = Capture()
    server = ThreadingHTTPServer(("0.0.0.0", free_port()), make_handler(capture))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    # Under the repo, not $TMPDIR: Podman/Docker VMs on macOS share /Users only.
    (GOLDEN_DIR / ".work").mkdir(exist_ok=True)
    workdir = Path(tempfile.mkdtemp(prefix=f"{output}-", dir=GOLDEN_DIR / ".work"))
    workdir.chmod(0o755)
    engine = ENGINES[engine_name](output, server.server_address[1], workdir, image)
    results: dict[str, dict] = {}
    try:
        engine.start()
        sock = _connect(engine)
        barrier = 0

        def send(line: str) -> None:
            nonlocal sock
            try:
                sock.sendall((line + "\n").encode("utf-8"))
            except OSError:
                sock = _connect(engine)
                sock.sendall((line + "\n").encode("utf-8"))

        # Readiness: repeat a barrier until one comes back.
        t0 = time.monotonic()
        while True:
            barrier += 1
            send(BARRIER_TEMPLATE.format(n=barrier))
            if capture.wait_barrier(barrier, 3.0):
                break
            if not engine.running():
                raise RuntimeError("engine container exited:\n" + engine.logs())
            if time.monotonic() - t0 > STARTUP_TIMEOUT:
                raise RuntimeError("engine never produced the barrier event:\n" + engine.logs())
        time.sleep(GRACE_SECONDS)
        capture.drain()
        if verbose:
            print(f"  [{output}] engine ready after {time.monotonic() - t0:.0f}s", flush=True)

        for case in cases:
            barrier += 1
            send(case.line)
            send(BARRIER_TEMPLATE.format(n=barrier))
            if not capture.wait_barrier(barrier, BARRIER_TIMEOUT):
                raise RuntimeError(f"barrier after case {case.id} never arrived:\n" + engine.logs())
            time.sleep(GRACE_SECONDS)
            results[case.id] = build_record(case, capture.drain())
            if verbose:
                n = sum(len(r["events"]) for r in results[case.id]["requests"])
                print(f"  [{output}] {case.id}: {n} event(s)", flush=True)
    finally:
        engine.stop()
        server.shutdown()
        shutil.rmtree(workdir, ignore_errors=True)
    return results


def _connect(engine) -> socket.socket:
    deadline = time.monotonic() + STARTUP_TIMEOUT
    while True:
        try:
            s = socket.create_connection(("127.0.0.1", engine.send_port), timeout=5)
            s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            return s
        except OSError:
            if not engine.running():
                raise RuntimeError("engine container exited:\n" + engine.logs()) from None
            if time.monotonic() > deadline:
                raise RuntimeError("could not connect to the engine's syslog port:\n"
                                   + engine.logs()) from None
            time.sleep(1)


# --------------------------------------------------------------------------- azure column contract

AZURE_SCHEMA_TF = ROOT / "deployments" / "azure-aci" / "module" / "ai" / "4-table-schemas.tf"
AZURE_PATH_TABLE = {
    "/azure/azure-suricata": "ids", "/azure/azure-mitm": "websession",
    "/azure/azure-microseg": "netsession", "/azure/azure-gw-net-stats": "gw_net_stats",
    "/azure/azure-gw-sys-stats": "gw_sys_stats", "/azure/azure-cmd": "cmd",
    "/azure/azure-tunnel-status": "tunnel_status", "/azure/azure-vpn-session": "vpn_session",
}
# Fields the DCR is expected to drop (not columns on purpose).
AZURE_EXPECTED_DROPS = {"tags", "@timestamp"}
# Columns the DCR transform fills from other columns (dcr_transform_prefix in
# 4-table-schemas.tf), so no Logstash event carries them.
AZURE_DCR_DERIVED = {"conntrack_usage_pct", "total_rx_bps", "total_tx_bps", "total_rx_tx_bps"}
# Known, accepted losses: session_id is a uint64 that can exceed the long column
# (NetworkSessionId carries it as a string); legacy microseg enforced="unknown".
AZURE_ACCEPTED = {("netsession", "session_id", "null"), ("netsession", "enforced", "null"),
                  ("gw_net_stats", "conntrack_usage_rate", "truncated"),
                  ("gw_net_stats", "total_rx_rate", "null"), ("gw_net_stats", "total_tx_rate", "null"),
                  ("gw_net_stats", "total_rx_tx_rate", "null")}


def azure_schemas() -> dict[str, dict[str, str]]:
    text = AZURE_SCHEMA_TF.read_text()
    tables, current = {}, None
    for line in text.splitlines():
        m = re.match(r"^\s{4}([a-z_]+) = \[", line)
        if m:
            current = tables.setdefault(m.group(1), {})
            continue
        m = re.search(r'name = "([^"]+)", type = "([^"]+)"', line)
        if m and current is not None:
            current[m.group(1)] = m.group(2)
    return tables


INT_RANGE = {"int": (-2**31, 2**31 - 1), "long": (-2**63, 2**63 - 1)}


def _azure_outcome(col_type: str, v) -> str:
    """What Log Analytics stores for value v in a column of col_type, given the
    DCR transform casts generated in 4-table-schemas.tf (dynamic stream column,
    then toint(toreal(x)) / tolong(x) / toreal(x) / tobool(x)). Measured against
    a live workspace 2026-11: JSON numbers and numeric strings both cast; a
    non-numeric string or an out-of-range value becomes null; int truncates.
    Returns "ok", "truncated" or "null"."""
    if v is None or col_type in ("string", "dynamic", "datetime"):
        return "ok" if col_type != "string" or isinstance(v, str) or v is None else "ok"
    if col_type == "boolean":
        if isinstance(v, bool) or (isinstance(v, str) and v.lower() in ("true", "false")):
            return "ok"
        return "null"
    if isinstance(v, bool):
        return "null"
    num = v
    if isinstance(v, str):
        try:
            num = int(v) if re.fullmatch(r"[+-]?\d+", v.strip()) else float(v)
        except ValueError:
            return "null"
    if not isinstance(num, (int, float)):
        return "null"
    if col_type == "real":
        return "ok"
    lo, hi = INT_RANGE[col_type]
    if not lo <= num <= hi:
        return "null"
    if isinstance(num, float) and not num.is_integer():
        return "truncated"
    return "ok"


def azure_columns_report(strict: bool) -> int:
    schemas = azure_schemas()
    sent: dict[str, dict[str, set]] = {}
    mismatches: dict[tuple, list] = {}
    problems = 0
    for f in sorted((EXPECTED_DIR / "azure-log-ingestion").glob("*.json")):
        rec = json.loads(f.read_text())
        for req in rec["requests"]:
            table = AZURE_PATH_TABLE.get(req["path"])
            if not table:
                print(f"  {rec['case']}: unknown Azure path {req['path']}")
                problems += 1
                continue
            cols = schemas.get(table, {})
            for ev in req["events"]:
                for k, v in ev.items():
                    sent.setdefault(table, {}).setdefault(k, set()).add(rec["case"])
                    outcome = _azure_outcome(cols[k], v) if k in cols and k not in TIME_KEYS else "ok"
                    if outcome != "ok":
                        mismatches.setdefault((table, k, cols[k], outcome), []).append(
                            (rec["case"], json.dumps(v)[:40]))
    for (table, k, col, outcome), hits in sorted(mismatches.items()):
        accepted = (table, k, outcome) in AZURE_ACCEPTED
        label = "accepted" if accepted else outcome.upper()
        print(f"  {label:9} {table}.{k}: {col} column stores {outcome} in {len(hits)} case(s), "
              f"e.g. {hits[0][0]} = {hits[0][1]}")
        problems += 0 if accepted else 1
    for table, fields in sorted(sent.items()):
        cols = schemas.get(table, {})
        dropped = sorted(k for k in fields if k not in cols and k not in AZURE_EXPECTED_DROPS)
        unused = sorted(c for c in cols if c not in fields and c != "TimeGenerated"
                        and c not in AZURE_DCR_DERIVED)
        for k in dropped:
            print(f"  DROPPED  {table}.{k}: sent (e.g. by {sorted(fields[k])[0]}) but not a column")
        if unused:
            print(f"  UNUSED   {table}: {len(unused)} column(s) no case populates: {', '.join(unused)}")
        problems += len(dropped) if strict else 0
    print(f"  {sum(len(v) for v in sent.values())} field/table pairs checked across {len(sent)} tables")
    return 1 if problems else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", choices=["generate", "check", "list", "azure-columns"])
    ap.add_argument("--engine", default="logstash", choices=sorted(ENGINES))
    ap.add_argument("--output", action="append", choices=OUTPUTS,
                    help="output(s) to run (default: all)")
    ap.add_argument("--case", action="append", default=[],
                    help="regex on case id; repeatable (default: all cases)")
    ap.add_argument("--corpus", action="append", type=Path, help="corpus file(s) (default: sample-logs/*.log)")
    ap.add_argument("--avx", metavar="RELEASE",
                    help="only cases an Aviatrix release emits, e.g. 9.0 (default: every case)")
    ap.add_argument("--image", default=LOGSTASH_IMAGE)
    ap.add_argument("--actual-dir", type=Path, help="check: also write actual records here")
    ap.add_argument("--strict", action="store_true",
                    help="azure-columns: also fail on fields the DCR would drop")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()
    if args.mode == "azure-columns":
        return azure_columns_report(args.strict)

    cases = load_corpus(args.corpus or DEFAULT_CORPUS)
    if args.case:
        rx = [re.compile(c) for c in args.case]
        cases = [c for c in cases if any(r.search(c.id) for r in rx)]
    if args.avx:
        cases = [c for c in cases if applies_to(c, args.avx)]
    if args.mode == "list":
        for c in cases:
            rng = (c.avx_min or "*") + ".." + (c.avx_until or "")
            print(f"{c.id:45} {rng:12} {c.source}")
        print(f"{len(cases)} cases")
        return 0
    if not cases:
        sys.exit("no cases selected")

    failures = 0
    for output in args.output or OUTPUTS:
        print(f"== {output}: {len(cases)} cases ({args.engine})", flush=True)
        results = run_output(args.engine, output, cases, args.image, args.verbose)
        out_dir = EXPECTED_DIR / output
        if args.mode == "generate":
            out_dir.mkdir(parents=True, exist_ok=True)
            if not args.case and not args.avx:  # full run: drop goldens for removed cases
                for stale in out_dir.glob("*.json"):
                    if stale.stem not in results:
                        stale.unlink()
            for cid, rec in results.items():
                (out_dir / f"{cid}.json").write_text(dumps(rec), encoding="utf-8")
            print(f"   wrote {len(results)} expected files to {out_dir.relative_to(ROOT)}")
            continue
        if args.actual_dir:
            (args.actual_dir / output).mkdir(parents=True, exist_ok=True)
        bad = 0
        for cid, rec in results.items():
            actual = dumps(rec)
            if args.actual_dir:
                (args.actual_dir / output / f"{cid}.json").write_text(actual, encoding="utf-8")
            exp_path = out_dir / f"{cid}.json"
            if not exp_path.exists():
                bad += 1
                print(f"   MISSING  {cid}: no expected file (run generate)")
                continue
            expected = exp_path.read_text(encoding="utf-8")
            if expected != actual:
                bad += 1
                print(f"   FAIL     {cid}")
                sys.stdout.writelines("     " + l for l in difflib.unified_diff(
                    expected.splitlines(True), actual.splitlines(True),
                    f"expected/{output}/{cid}.json", "actual", n=2))
        print(f"   {len(results) - bad} passed, {bad} failed")
        failures += bad
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
