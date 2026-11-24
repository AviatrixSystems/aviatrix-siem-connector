# Webhook Viewer

A self-hosted webhook viewer for testing HTTP webhook endpoints. Uses [tarampampam/webhook-tester](https://github.com/tarampampam/webhook-tester) - a lightweight Go-based alternative to webhook.site.

## Features

- **Real-time updates**: WebSocket support for instant webhook notifications
- **Web UI**: Built-in ReactJS interface for viewing requests
- **No external dependencies**: Standalone with in-memory storage
- **Custom responses**: Configure response codes, headers, and body content
- **Container-ready**: Simple Docker deployment

## Quick Start (Local)

```bash
cd local
./run.sh
```

Then open http://localhost:8080 in your browser.

## Usage

### Start the viewer

```bash
# Default port 8080
./local/run.sh

# Custom port
./local/run.sh 9000
```

### Commands

```bash
./local/run.sh start [port]  # Start the viewer
./local/run.sh stop          # Stop the viewer
./local/run.sh restart       # Restart the viewer
./local/run.sh logs          # View container logs
./local/run.sh status        # Check if running
./local/run.sh help          # Show help
```

### Creating a webhook endpoint

1. Open the UI in your browser (http://localhost:8080)
2. Click "New" to create a session
3. Copy the generated webhook URL
4. Send requests to that URL - they'll appear in real-time

## Testing with Logstash

Use the `webhook-test` output, which sends the same Splunk HEC-shaped payloads as
`splunk-hec` (`{sourcetype, source, host, time, event}`) and honors `LOG_PROFILE`.
Pass the session URL as `WEBHOOK_URL`. When Logstash runs in Docker, `localhost`
is the Logstash container itself, so use `host.docker.internal`:

```bash
cd ../../logstash-configs
./scripts/assemble-config.sh webhook-test
docker run --rm -p 5002:5000/udp -p 5002:5000/tcp \
  -v "$(pwd)/assembled:/config" \
  -v "$(pwd)/patterns:/usr/share/logstash/patterns" \
  -e WEBHOOK_URL=http://host.docker.internal:8080/<session-id> \
  docker.elastic.co/logstash/logstash:8.16.2 \
  logstash -f /config/webhook-test-full.conf
```

See [CONTRIBUTING.md](../../CONTRIBUTING.md) for the full test loop.

## Directory Structure

```
webhook-viewer/
├── local/          # Local Docker-based setup
│   └── run.sh      # Start/stop script
└── README.md
```

## Requirements

- Docker installed and running
- Port 8080 (or custom) available
