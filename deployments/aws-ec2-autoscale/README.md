# AWS EC2 Autoscale Deployment

This deployment creates a highly available, auto-scaling cluster of EC2 instances running the Aviatrix SIEM Connector with Logstash behind a Network Load Balancer.

## Architecture

- Network Load Balancer (NLB) for high availability
- Auto Scaling Group (2-6 instances recommended)
- EC2 instances (t3.small recommended) running Logstash containers
- Logstash listening on `syslog_port` (default 5000, UDP or TCP), or mTLS on `tls_port` with `tls_enabled`
- Configuration stored in S3; credentials (the rendered `docker run` command) in Secrets Manager (`avxlog-<suffix>-runtime`), fetched at boot
- Rolling instance refresh when the config, patterns or credentials change
- ELB health checks replace unhealthy instances
- CPU-based step scaling (up and down)

```
Aviatrix → NLB → Auto Scaling Group → EC2 Instances (Logstash) → Splunk/SIEM
```

## Prerequisites

1. **AWS Account** with appropriate IAM permissions
2. **Optional SSH Key Pair**. SSH is closed by default (`ssh_allowed_cidrs = []`); instances have `AmazonSSMManagedInstanceCore` for SSM Session Manager
3. **VPC with Multiple Subnets** across different AZs for high availability
4. **Splunk HEC Token** (if using Splunk output)
   - Get from Splunk: Settings → Data Inputs → HTTP Event Collector
   - Note the private IP of your Splunk server

## Quick Start

### 1. Assemble the Logstash Config

First, generate the full Logstash configuration:

```bash
cd ../../logstash-configs
./scripts/assemble-config.sh splunk-hec
# This creates assembled/splunk-hec-full.conf
```

Terraform reads `assembled/<output_type>-full.conf` and `outputs/<output_type>/docker_run.tftpl` directly.

### 2. Configure Terraform Variables

```bash
cd ../deployments/aws-ec2-autoscale
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
# Network - MUST be able to reach Splunk server
vpc_id = "vpc-xxxxx"

# Use subnets in different AZs for high availability
instance_subnet_ids = [
  "subnet-xxxxx",  # AZ 1
  "subnet-yyyyy"   # AZ 2
]

lb_subnet_ids = [
  "subnet-xxxxx",  # AZ 1
  "subnet-yyyyy"   # AZ 2
]

# Autoscaling
autoscale_min_size = 2
autoscale_max_size = 6
autoscale_step_size = 2

# Restrict syslog to your gateway/controller egress IPs (default 0.0.0.0/0).
# NLB health checks get their own rule from the VPC CIDR.
allowed_syslog_cidrs = ["203.0.113.10/32"]

# Splunk Configuration - UPDATE THESE! (splunk_address must include https://)
output_type = "splunk-hec"
logstash_config_variables = {
  "splunk_hec_auth" = "your-actual-hec-token-here"
  "splunk_address" = "https://10.x.x.x"  # Private IP of Splunk in same VPC
  "splunk_port" = "8088"
}
```

**IMPORTANT Configuration Notes:**
- Use subnets in **different Availability Zones** for high availability
- Use the **private IP** of your Splunk server if it's in the same VPC
- Ensure the VPC/subnets have routing to reach Splunk
- The HEC token must be valid
- Dynatrace, Zabbix and Azure examples are in `terraform.tfvars.example`. `zabbix` and `azure-log-ingestion` require `logstash_image` (an image FROM stock Logstash with the plugin, e.g. built from `logstash-configs/outputs/zabbix/Containerfile`); plan fails without it

### 3. Deploy

```bash
terraform init
terraform plan
terraform apply
```

### 4. Get the Syslog Endpoint

After deployment:

```bash
terraform output
```

Example output:
```
avx_syslog_destination = "avxlog-abc123-1234567890.elb.us-east-2.amazonaws.com"
avx_syslog_port = "5000"
avx_syslog_proto = "tcp"
```

### 5. Configure Aviatrix

**Controller:**
- Settings → Logging → Remote Syslog
- Server: `<avx_syslog_destination>` from Terraform output
- Port: `<avx_syslog_port>` (5000, or `tls_port` with TLS)
- Protocol: `TCP` (or UDP if `syslog_protocol = "udp"`)

**Gateways:** (configure each)
- Same settings as controller

## High Availability Features

### Load Balancing
- NLB distributes syslog traffic across multiple instances
- TCP health checks (from the VPC CIDR, also for UDP listeners) ensure only healthy instances receive traffic
- The target group uses `deregistration_delay` (default 60s) and closes flows on deregistration, so TCP senders reconnect to a live instance
- TCP syslog flows stay pinned to one instance until they reconnect, so new instances mainly pick up new connections; UDP spreads load better
- Cross-AZ deployment for regional resilience

### Auto Scaling
- **Scale Up:** CPU >= 75% for 2 × 2 minutes adds `autoscale_step_size` instances
- **Scale Down:** CPU <= 25% for 4 × 2 minutes removes `autoscale_step_size` instances
- **Health:** `health_check_type = "ELB"` with `health_check_grace_period` (default 600s) for bootstrap
- **Instance Refresh:** rolling, 50% minimum healthy, triggered when the config, patterns or credentials change (they are part of the launch template's user_data)
- **AMI:** a newer AL2023 AMI also triggers a refresh unless `ami_id` is pinned

### Config Updates
When you update the Logstash configuration:
1. Modify source config in `logstash-configs/`
2. Reassemble: `./scripts/assemble-config.sh splunk-hec`
3. Apply: `terraform apply`
4. ASG performs a rolling instance refresh. Capacity stays at >= 50%, but TCP senders on replaced instances are disconnected and must reconnect, and UDP datagrams in flight to a terminating instance can be lost

## Testing

Use the test tools to verify logs flow through the NLB to Splunk:

```bash
cd ../../test-tools/sample-logs
./generate-current-samples.sh -o /tmp/samples-now.log
./stream-logs.py -f /tmp/samples-now.log --target <nlb_dns> --tcp --filter microseg -v
./stream-logs.py --target <nlb_dns> --tcp --filter cmd -v
```

Check Splunk for events:
```
index=* sourcetype=aviatrix:*
```

## Troubleshooting

### Logs not reaching Splunk

1. **Check NLB health checks:**
   ```bash
   aws elbv2 describe-target-health --target-group-arn <tg-arn>
   ```
   All instances should show "healthy"

2. **Check Logstash logs on an instance** (`aws ssm start-session --target <instance-id>`, or SSH if `ssh_allowed_cidrs` is set):
   ```bash
   sudo docker ps
   sudo docker logs <logstash-container> --tail 50
   ```

3. **Common errors:**
   - `403 Invalid token` → HEC token is wrong
   - `No route to host` → Network connectivity issue to Splunk
   - `Connection refused` → Splunk HEC not enabled or wrong port

4. **Test Splunk HEC manually from an instance:**
   ```bash
   curl -k -H "Authorization: Splunk <token>" \
     https://<splunk-ip>:8088/services/collector/event \
     -d '{"event":"test"}'
   ```

### Instances unhealthy

1. **Check instance logs** (in an SSM/SSH session):
   ```bash
   sudo journalctl -u docker
   sudo cat /var/log/cloud-init-output.log   # boot script, secret fetch retries
   ```

2. **Verify config files:**
   ```bash
   ls -la /logstash/pipeline/
   ls -la /logstash/patterns/
   ```

3. **Check S3 access:**
   ```bash
   aws s3 ls s3://avxlog-<random>/
   ```

### Auto-scaling not working

1. **Check CloudWatch alarms:**
   ```bash
   aws cloudwatch describe-alarms --alarm-name-prefix avxlog
   ```

2. **Review ASG activity:**
   ```bash
   aws autoscaling describe-scaling-activities --auto-scaling-group-name <asg-name>
   ```

## Performance Tuning

### Instance Sizing
- **t3.small:** Up to 1,000 EPS (events per second)
- **t3.medium:** Up to 5,000 EPS
- **t3.large:** Up to 10,000 EPS

### Scaling Configuration
Adjust based on your traffic patterns:
```hcl
autoscale_min_size = 2      # Always maintain 2 instances
autoscale_max_size = 10     # Scale up to 10 during peak
autoscale_step_size = 2     # Add 2 instances at a time
```

### CPU Threshold
Edit the `aws_cloudwatch_metric_alarm` resources in [main.tf](main.tf) to adjust the scaling trigger:
```hcl
threshold = 75  # Scale up when CPU > 75%
```

## Cost Optimization

- **Minimum Instances:** Set to 2 for HA, or 1 to save costs (no HA)
- **Instance Type:** t3.small is sufficient for most deployments
- **Storage:** 30GB gp3 root volume
- **Spot Instances:** Not recommended (would cause data loss during interruptions)

## Security Considerations

- Syslog is open to `0.0.0.0/0` by default; set `allowed_syslog_cidrs` in production
- No SSH ingress unless `ssh_allowed_cidrs` is set; use SSM Session Manager
- Credentials are stored in Secrets Manager and passed to the container as environment variables at boot
- SSL verification disabled for Splunk HEC (use proper certs in production)

## Monitoring

### CloudWatch Metrics
Key metrics to monitor:
- **ASG:** GroupDesiredCapacity, GroupInServiceInstances
- **EC2:** CPUUtilization, NetworkIn, NetworkOut
- **NLB:** ActiveFlowCount, HealthyHostCount, ProcessedBytes

### Alarms
Pre-configured alarms:
- High CPU (triggers scale-up)

Consider adding:
- Unhealthy host count
- NLB connection errors
- Instance status check failures

## Comparison: Single-Instance vs Autoscale

| Feature | Single-Instance | Autoscale |
|---------|----------------|-----------|
| **HA** | No (single point of failure) | Yes (multi-AZ, auto-healing) |
| **Scalability** | Fixed capacity | Dynamic (2-6+ instances) |
| **Cost** | ~$30/month (t3.small) | ~$60-180/month (2-6 × t3.small + NLB) |
| **Deployment** | Simpler | More complex |
| **Maintenance** | Replaced on config change (brief outage) | Auto-healing, rolling updates |
| **Best For** | Dev/test, small environments | Production, high-volume |

## Variables

Beyond the network, autoscaling and `logstash_config_variables` inputs above (see [variables.tf](variables.tf)):

| Variable | Default | Description |
|---|---|---|
| `output_type` | `splunk-hec` | Directory under `logstash-configs/outputs/` |
| `allowed_syslog_cidrs` | `["0.0.0.0/0"]` | Syslog/TLS source CIDRs |
| `ssh_allowed_cidrs` | `[]` | SSH source CIDRs; empty creates no SSH rule |
| `ssh_key_name` | `logstash` | Key pair name; empty for none |
| `ami_id` | `""` | Pin the AMI; empty uses the latest AL2023 |
| `health_check_grace_period` | `600` | Seconds before ELB health checks count |
| `deregistration_delay` | `60` | NLB target drain time in seconds |
| `syslog_port` / `syslog_protocol` | `5000` / `tcp` | Non-5000 ports need a reassembled config |
| `tls_enabled`, `tls_port`, ... | `false`, `6514` | mTLS via a stunnel container on the host network |

## Files

- [main.tf](main.tf) - Module call, launch template, ASG, scaling, NLB
- [tls.tf](tls.tf) - Optional TLS certificates
- [variables.tf](variables.tf) - Variable definitions
- [outputs.tf](outputs.tf) - Output values
- [terraform.tfvars.example](terraform.tfvars.example) - Example configuration
- [../modules/aws-logstash/](../modules/aws-logstash/) - Shared S3, IAM, security group, Secrets Manager and user data (`logstash_instance_init.tftpl`)

## Related Documentation

- [Single-Instance Deployment](../aws-ec2-single-instance/README.md) - Simpler alternative
- [Project Overview](../../CLAUDE.md) - Full project documentation
- [Contributing](../../CONTRIBUTING.md) - Sample logs and testing workflow
