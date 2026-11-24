# Golden input/output tests

These tests pin down exactly what the connector emits for each sample line, field by field. They are the safety net for porting the pipeline to another engine (Fluent Bit) and for any filter change. CI's `validate-output.sh` only checks per-type counts; this checks content.

```
test-tools/sample-logs/*.log    corpus: one sample line per case, each with a "# @case" annotation
test-tools/golden/golden.py     runner: engine in a container + local HTTP capture server
test-tools/golden/expected/     one JSON file per output and case (commit these)
  parsed/                       the whole event after the filter stage
  splunk-hec/                   exact HEC request bodies (path, auth scheme, events)
  dynatrace-logs/               exact Dynatrace log ingest bodies
  azure-log-ingestion/          the record sent per DCR stream (path = stream)
```

## Usage

```bash
cd test-tools/golden
./golden.py list                                   # cases with their Aviatrix release range
./golden.py check                                  # all outputs, all cases (~2 min per output)
./golden.py check --output parsed --case '^mitm-'  # fast loop while editing one filter
./golden.py check --avx 9.0                        # only cases a 9.0 gateway/controller emits
./golden.py generate --output splunk-hec           # accept the current behavior as expected
./golden.py azure-columns                          # fields the DCR would drop, type mismatches
```

`check` prints a unified diff per failing case and exits 1. `--actual-dir DIR` also writes what the engine produced, so you can diff whole trees.

Only run `generate` after you have reviewed the diff from `check` and the change is intended. The expected files are the contract.

## Corpus annotations

Every sample line must be preceded by a case annotation. Lines starting with `#` are ignored by `stream-logs.py`, `update-timestamps.py` and `validate-output.sh`, so the annotations don't affect the E2E test.

```
# --- free-text description ---
# @case microseg-82-deny-not-enforced avx=8.2
<134>Mar  4 22:55:10 GW-... AviatrixGwMicrosegPacket: POLICY=... ACTION=DENY ENFORCED=false
```

- `id` must be lowercase `[a-z0-9._-]`, unique across all corpus files, and stable. It is the expected file's name.
- `avx=<release>` is the first Aviatrix release that emits this exact format.
- `until=<release>` is the last release that emits it, if the format was later changed or removed.
- With no `avx`/`until`, the case applies to every release.

`--avx 10.1` selects the cases a 10.1 deployment produces. This lets one corpus serve several releases: legacy 7.x microseg, 8.2 session fields, 9.0 changes, 10.1 OTLP.

## How it works

1. The output's config is assembled with `logstash-configs/scripts/assemble-config.sh`. HTTP outputs are pointed at a capture server on the host via env vars (`SPLUNK_ADDRESS`, `DT_LOGS_URL`).
   - For `azure-log-ingestion`, the 8 Sentinel plugin blocks are swapped for `http` outputs posting to `/azure/<plugin-id>`, because the plugin needs real Entra ID credentials.
   - For `parsed`, the ci-test output is swapped for an `http` output that posts the whole event.
2. The engine runs in a container with one pipeline worker, so events come out in order.
3. Each case line is sent over TCP. A **barrier** line follows it: a tunnel-status event carrying `golden-barrier-<n>`. Once the barrier reaches the capture server, everything the case produced has been sent. Barrier events are removed from the recorded output.
4. Recorded requests are normalized and written as sorted, pretty JSON:
   - `@version` is dropped.
   - Floats that are whole numbers become ints (`1.0` → `1`).
   - Events within a request are sorted.
   - **Years are masked** (`YYYY-03-04T…`) in time fields (`@timestamp`, `timestamp`, `time`, `unix_time`, `TimeGenerated`, `EventStartTime`, `EventEndTime`) and in any string that is entirely an ISO-8601 timestamp. Syslog headers have no year, so the engine assigns the current one. Month, day and time of day must still match.
   - **Receive-time timestamps** become `<receive time>`. This covers any timestamp within 30 minutes of the run. An event whose header couldn't be parsed carries the engine's clock, which differs on every run. Corpus timestamps are never that close to "now".
   - **JSON embedded in a string** (for example the Splunk MITM `event`, which is a JSON-encoded string) is compared decoded, as `{"__json_string__": {...}}`. The engine doesn't keep its key order stable.

A case that produces no output (dropped or unparsed) gets an expected file with `"requests": []`, so a line that starts being forwarded is also caught.

## Adding an engine

`golden.py` has an `ENGINES` map. A new engine class needs to:

- Accept syslog on TCP inside the container and publish it with `-p 127.0.0.1:<send_port>:<port>/tcp`.
- Send each destination's requests to `GOLDEN_CAPTURE_URL` (`http://host.docker.internal:<port>`) using the same paths:
  - `/services/collector/event` for Splunk
  - `/dynatrace/logs`
  - `/azure/<plugin-id>`
  - `/parsed`
- Implement `start()`, `running()`, `logs()` and `stop()`.

Then `./golden.py check --engine fluentbit` diffs it against the same expected files. Run it as `--engine fluentbit --output parsed` too, but expect `parsed` to differ by design once the canonical record replaces Logstash's internal field names. Destination payloads are what must match.

## Podman / Docker notes

- The scratch config goes under `test-tools/golden/.work/` (gitignored), not `$TMPDIR`. On macOS, Podman and Docker Desktop VMs share `/Users` only.
- `--add-host host.docker.internal:host-gateway` is passed explicitly, so this also works on Linux CI.
