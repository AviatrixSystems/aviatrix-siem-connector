# AWS EC2 Single Instance Deployment

This deployment creates a single EC2 instance running the Aviatrix Log Integration Engine with Logstash.

## Architecture

- Single EC2 instance (t3.small recommended)
- Logstash Docker container listening on port 5000 (UDP/TCP)
- Configuration stored in S3 bucket
- Automatic updates via lifecycle policy when configs change

## Prerequisites

1. **AWS Account** with appropriate IAM permissions
2. **SSH Key Pair** in the target AWS region
3. **VPC and Subnet** that can reach your Splunk/SIEM server
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

### 2. Copy docker_run.tftpl to assembled directory

```bash
cp outputs/splunk-hec/docker_run.tftpl assembled/
```

### 3. Configure Terraform Variables

```bash
cd ../deployment-tf/aws-ec2-single-instance
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
# Network - MUST be able to reach Splunk server
vpc_id = "vpc-xxxxx"
subnet_id = "subnet-xxxxx"

# Splunk Configuration - UPDATE THESE!
logstash_config_variables = {
  "splunk_hec_auth" = "your-actual-hec-token-here"
  "splunk_address" = "https://10.x.x.x"  # Private IP of Splunk in same VPC
  "splunk_port" = "8088"
}
```

**IMPORTANT Configuration Notes:**
- Use the **private IP** of your Splunk server if it's in the same VPC
- Ensure the VPC/subnet has routing to reach Splunk
- The HEC token must be valid (test with: `curl -k -H "Authorization: Splunk <token>" https://splunk-ip:8088/services/collector/event`)

### 4. Deploy

```bash
terraform init
terraform plan
terraform apply
```

### 5. Get the Syslog Endpoint

After deployment:

```bash
terraform output
```

Example output:
```
avx_syslog_destination = "3.149.143.152"
avx_syslog_port = "5000"
avx_syslog_proto = "tcp"
```

### 6. Configure Aviatrix

**Controller:**
- Settings → Logging → Remote Syslog
- Server: `<avx_syslog_destination>`
- Port: `5000`
- Protocol: `TCP`

**Gateways:** (configure each)
- Same settings as controller

## Testing

Use the test tools to verify logs flow to Splunk:

```bash
cd ../../test-tools/sample-logs
./stream-logs.py --target <syslog_ip> --tcp --filter microseg -v
./stream-logs.py --target <syslog_ip> --tcp --filter cmd -v
```

Check Splunk for events:
```
index=* sourcetype=aviatrix:*
```

## Troubleshooting

### Logs not reaching Splunk

1. **Check Logstash logs:**
   ```bash
   ssh -i <key>.pem ec2-user@<instance-ip>
   sudo docker logs $(sudo docker ps -q) | tail -50
   ```

2. **Look for errors:**
   - `403 Invalid token` → HEC token is wrong
   - `No route to host` → Network connectivity issue between instance and Splunk
   - `Connection refused` → Splunk HEC not enabled or wrong port

3. **Test Splunk HEC manually:**
   ```bash
   curl -k -H "Authorization: Splunk <token>" \
     https://<splunk-ip>:8088/services/collector/event \
     -d '{"event":"test"}'
   ```

### Config not loading

1. **Check files are in place:**
   ```bash
   ls -la /logstash/pipeline/
   ls -la /logstash/patterns/
   ```

2. **Check S3 bucket:**
   ```bash
   aws s3 ls s3://avx-log-int-<random>/
   ```

### Instance keeps recreating

This is by design when configs change. The `lifecycle` block triggers replacement when S3 objects change.

## Updating Configuration

1. Modify the source config in `logstash-configs/`
2. Reassemble: `./scripts/assemble-config.sh splunk-hec`
3. Apply changes: `terraform apply`
4. The instance will be recreated with new config

## Cost Optimization

- **Instance Type:** t3.small is recommended for moderate traffic (< 1000 EPS)
- **For higher throughput:** Use t3.medium or consider the autoscale deployment
- **Storage:** 20GB root volume is sufficient for logs buffering

## Security Considerations

- Security group allows 0.0.0.0/0 on port 5000 by default
- Restrict `syslog_cidr_blocks` in a production environment
- Splunk HEC token is passed as environment variable (sensitive)
- SSL verification is disabled for Splunk HEC (use proper certs in production)

## Files

- `main.tf` - Main infrastructure resources
- `variables.tf` - Variable definitions
- `output.tf` - Output values
- `terraform.tfvars.example` - Example configuration
- `logstash_instance_init.tftpl` - EC2 user data script
