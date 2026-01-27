# Logstash Configuration

This directory contains modular Logstash configuration files for parsing Aviatrix syslog messages and forwarding them to various SIEM/observability platforms.

## Quick Start

### 1. Assemble a Configuration

```bash
# For Splunk HEC output
./scripts/assemble-config.sh splunk-hec

# For Azure Log Analytics output
./scripts/assemble-config.sh azure-log-ingestion
```

This creates a complete configuration file in `assembled/`.

### 2. Deploy

Copy the assembled config and patterns to your Logstash instance:

```bash
# Copy assembled config to Logstash pipeline directory
cp assembled/splunk-hec-full.conf /usr/share/logstash/pipeline/

# Copy patterns
cp patterns/avx.conf /usr/share/logstash/patterns/
```

### 3. Set Environment Variables

See the output-specific README in `outputs/<type>/` for required environment variables.

## Directory Structure

```
logstash-configs/
├── inputs/                 # Input configurations (syslog listener)
├── filters/                # Filter modules (parsing, transformation)
├── outputs/                # Output configurations by destination
│   ├── splunk-hec/         # Splunk HTTP Event Collector
│   └── azure-log-ingestion/# Azure Log Analytics via DCR
├── patterns/               # Custom grok patterns
├── assembled/              # Generated complete configs (do not edit)
└── scripts/                # Build tools
```

## Building Configurations

### Assembly Script

The `scripts/assemble-config.sh` script combines modular configs into a single deployable file:

```bash
./scripts/assemble-config.sh <output-type> [destination-path]

# Examples:
./scripts/assemble-config.sh splunk-hec                    # Output to assembled/splunk-hec-full.conf
./scripts/assemble-config.sh azure-log-ingestion           # Output to assembled/azure-log-ingestion-full.conf
./scripts/assemble-config.sh splunk-hec /tmp/logstash.conf # Custom output path
```

### Filter Processing Order

Filters are processed in numerical order by filename:

| File | Purpose |
|------|---------|
| `10-fqdn.conf` | FQDN firewall rule parsing |
| `11-cmd.conf` | Controller API call parsing |
| `12-microseg.conf` | L4 microsegmentation (eBPF) |
| `13-l7-dcf.conf` | L7 DCF/TLS inspection |
| `14-suricata.conf` | Suricata IDS alerts |
| `15-gateway-stats.conf` | Gateway performance metrics |
| `16-tunnel-status.conf` | Tunnel state changes |
| `80-throttle.conf` | Rate limiting for microseg logs |
| `90-timestamp.conf` | Timestamp normalization |
| `95-field-conversion.conf` | Field type conversions |

## Adding a New Output Type

1. Create a new directory under `outputs/`:
   ```bash
   mkdir -p outputs/my-new-output
   ```

2. Create `outputs/my-new-output/output.conf` with your output configuration:
   ```ruby
   output {
       if "microseg" in [tags] {
           # your output plugin config
       }
       # ... other tag conditions
   }
   ```

3. Assemble and test:
   ```bash
   ./scripts/assemble-config.sh my-new-output
   logstash -f assembled/my-new-output-full.conf --config.test_and_exit
   ```

## Modifying Filters

Edit files in `filters/` directly. Changes apply to ALL output types when you reassemble.

**To add a new log type:**
1. Create `filters/1X-newtype.conf` (choose appropriate number for ordering)
2. Follow the pattern of existing filters (check tags, add tags on match)
3. Reassemble all output configs

**To modify parsing:**
1. Edit the appropriate filter file
2. Reassemble all output configs
3. Test with sample logs

## Testing

### Validate Configuration Syntax

```bash
logstash -f assembled/splunk-hec-full.conf --config.test_and_exit
```

### Test with Sample Data

```bash
# Send a test syslog message
echo '<134>Dec  8 12:00:00 GW-test-gw-10.0.0.1 test message' | nc -u localhost 5000
```

## Supported Log Types

| Tag | Source | Description |
|-----|--------|-------------|
| `fqdn` | AviatrixFQDNRule | DNS/FQDN firewall rules |
| `cmd` | AviatrixCMD, AviatrixAPI | Controller API calls |
| `microseg` | AviatrixGwMicrosegPacket | L4 microsegmentation |
| `mitm` | traffic_server | L7/TLS inspection |
| `suricata` | suricata JSON | IDS/IPS alerts |
| `gw_net_stats` | AviatrixGwNetStats | Gateway network stats |
| `gw_sys_stats` | AviatrixGwSysStats | Gateway system stats |
| `tunnel_status` | AviatrixTunnelStatusChange | Tunnel state changes |
