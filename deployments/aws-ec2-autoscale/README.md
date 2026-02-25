# AWS EC2 Autoscale Deployment

This deployment creates a highly available, auto-scaling cluster of EC2 instances running the Aviatrix Log Integration Engine with Logstash behind a Network Load Balancer.

## Architecture

- Network Load Balancer (NLB) for high availability
- Auto Scaling Group (2-6 instances recommended)
- EC2 instances (t3.small recommended) running Logstash containers
- Logstash listening on port 5000 (UDP/TCP)
- Configuration stored in S3 bucket
- Automatic rolling updates when configs change
- CPU-based auto-scaling policies

```
Aviatrix → NLB → Auto Scaling Group → EC2 Instances (Logstash) → Splunk/SIEM
```

## Prerequisites

1. **AWS Account** with appropriate IAM permissions
2. **SSH Key Pair** in the target AWS region
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

### 2. Copy docker_run.tftpl to assembled directory

```bash
cp outputs/splunk-hec/docker_run.tftpl assembled/
```

### 3. Configure Terraform Variables

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

# Splunk Configuration - UPDATE THESE!
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
nlb_dns_name = "avxlog-abc123-1234567890.elb.us-east-2.amazonaws.com"
avx_syslog_destination = "avxlog-abc123-1234567890.elb.us-east-2.amazonaws.com"
avx_syslog_port = "5000"
avx_syslog_proto = "tcp"
```

### 6. Configure Aviatrix

**Controller:**
- Settings → Logging → Remote Syslog
- Server: `<nlb_dns_name>` from Terraform output
- Port: `5000`
- Protocol: `TCP`

**Gateways:** (configure each)
- Same settings as controller

## High Availability Features

### Load Balancing
- NLB distributes syslog traffic across multiple instances
- Health checks ensure only healthy instances receive traffic
- Cross-AZ deployment for regional resilience

### Auto Scaling
- **Scale Up:** Triggered when CPU > 75% for 4 minutes
- **Scale Down:** Manual or time-based (not automatic)
- **Rolling Updates:** 50% minimum healthy during config changes
- **Instance Refresh:** Triggered automatically when S3 config changes

### Config Updates
When you update the Logstash configuration:
1. Modify source config in `logstash-configs/`
2. Reassemble: `./scripts/assemble-config.sh splunk-hec`
3. Apply: `terraform apply`
4. ASG performs rolling instance refresh (no downtime)

## Testing

Use the test tools to verify logs flow through the NLB to Splunk:

```bash
cd ../../test-tools/sample-logs
./stream-logs.py --target <nlb_dns> --tcp --filter microseg -v
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

2. **Check Logstash logs on an instance:**
   ```bash
   ssh -i <key>.pem ec2-user@<instance-ip>
   sudo docker logs $(sudo docker ps -q) | tail -50
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

1. **Check instance logs:**
   ```bash
   ssh -i <key>.pem ec2-user@<instance-ip>
   sudo journalctl -u docker
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
Edit [main.tf](main.tf#L206-L216) to adjust the scaling trigger:
```hcl
threshold = 75  # Scale up when CPU > 75%
```

## Cost Optimization

- **Minimum Instances:** Set to 2 for HA, or 1 to save costs (no HA)
- **Instance Type:** t3.small is sufficient for most deployments
- **Storage:** 20GB root volume is sufficient for log buffering
- **Spot Instances:** Not recommended (would cause data loss during interruptions)

## Security Considerations

- Security group allows 0.0.0.0/0 on port 5000 by default
- Restrict `syslog_cidr_blocks` in production (requires main.tf edit)
- Splunk HEC token passed as environment variable (sensitive)
- SSL verification disabled for Splunk HEC (use proper certs in production)
- Instances use IMDSv2 for metadata access (recommended)

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
| **Maintenance** | Manual replacement | Auto-healing, rolling updates |
| **Best For** | Dev/test, small environments | Production, high-volume |

## Files

- [main.tf](main.tf) - Main infrastructure resources
- [variables.tf](variables.tf) - Variable definitions
- [output.tf](output.tf) - Output values
- [terraform.tfvars.example](terraform.tfvars.example) - Example configuration
- [logstash_instance_init.tftpl](logstash_instance_init.tftpl) - EC2 user data script

## Related Documentation

- [Single-Instance Deployment](../aws-ec2-single-instance/README.md) - Simpler alternative
- [Project Overview](../../CLAUDE.md) - Full project documentation
- [Testing Tools](../../test-tools/README.md) - Sample logs and testing utilities
