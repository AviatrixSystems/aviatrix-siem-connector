# Splunk HTTP Event Collector Output

This output configuration sends parsed Aviatrix logs to Splunk via the HTTP Event Collector (HEC).

## Quick Start

### 1. Build the Configuration

```bash
cd logstash-configs
./scripts/assemble-config.sh splunk-hec
```

This creates `assembled/splunk-hec-full.conf`.

### 2. Configure Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `SPLUNK_ADDRESS` | Splunk server hostname/IP (include protocol, e.g., `https://splunk.example.com`) | (required) |
| `SPLUNK_PORT` | HEC port | 8088 |
| `SPLUNK_HEC_AUTH` | HEC authentication token | (required) |

### 3. Run Logstash

```bash
docker run -d --restart=always \
  --name logstash-aviatrix \
  -v /path/to/assembled/splunk-hec-full.conf:/usr/share/logstash/pipeline/logstash.conf \
  -v /path/to/patterns:/usr/share/logstash/patterns \
  -e SPLUNK_ADDRESS=https://splunk.example.com \
  -e SPLUNK_PORT=8088 \
  -e SPLUNK_HEC_AUTH=your-hec-token \
  -e XPACK_MONITORING_ENABLED=false \
  -p 5000:5000/tcp \
  -p 5000:5000/udp \
  docker.elastic.co/logstash/logstash:8.16.2
```

## Configuring Splunk HEC

1. From the Splunk dashboard, go to **Settings > Data Inputs > HTTP Event Collector**
2. Click **New Token** to create a token for Aviatrix
3. Configure the token:
   - Name: `aviatrix-logs`
   - Source type: `_json` (or create custom sourcetypes)
   - Index: Select your target index
4. Copy the token value and use it as `SPLUNK_HEC_AUTH`

## Source Types

The configuration sends logs with the following source values:

| Log Type | Source | Description |
|----------|--------|-------------|
| Suricata IDS | `avx-ids` | IDS/IPS alerts |
| L7 DCF/MITM | `avx-l7-fw` | TLS inspection events |
| L4 Microseg | `avx-l4-fw` | eBPF microsegmentation |
| FQDN | `avx-fqdn` | DNS/FQDN firewall |
| Controller API | `avx-cmd` | API audit logs |
| Network Stats | `avx-gw-net-stats` | Gateway throughput |
| System Stats | `avx-gw-sys-stats` | Gateway CPU/memory |
| Tunnel Status | `avx-tunnel-status` | Tunnel state changes |

## Terraform Deployment

For AWS deployments, use the following variables:

```hcl
logstash_config_variables = {
  "splunk_hec_auth" = "your-hec-token"
  "splunk_port"     = "8088"
  "splunk_address"  = "https://splunk.example.com"
}
```

Example `terraform.tfvars` for `aws-ec2-single-instance`:

```hcl
aws_region                  = "us-east-2"
logstash_instance_size      = "t3.small"
syslog_port                 = "5000"
vpc_id                      = "vpc-12345"
subnet_id                   = "subnet-12345"
ssh_key_name                = "aws-ssh-key"
logstash_output_config_path = "../../logstash-configs/assembled"
logstash_output_config_name = "splunk-hec-full.conf"
logstash_config_variables = {
  "splunk_hec_auth" = "your-hec-token"
  "splunk_port"     = "8088"
  "splunk_address"  = "https://splunk.example.com"
}
```

## SSL Configuration

By default, SSL verification is disabled (`ssl_verification_mode => "none"`). For production, configure proper SSL:

1. Obtain Splunk's CA certificate
2. Mount the certificate in the container
3. Modify `output.conf` to set `ssl_verification_mode => "full"` and `cacert => "/path/to/ca.crt"`
