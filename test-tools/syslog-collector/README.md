# Syslog Collector AWS Infrastructure

This directory contains Terraform configuration to deploy a self-contained syslog collector in AWS for testing purposes.

## Overview

The infrastructure includes:
- **VPC**: A dedicated VPC with public subnet and internet gateway
- **EC2 Instance**: Amazon Linux 2 instance with Docker and syslog services
- **Security Group**: Configured for syslog (port 514 UDP/TCP), SSH, and web UI access
- **Elastic IP**: Static public IP for consistent endpoint
- **Web UI**: Password-protected interface for downloading collected logs

## Features

- **Syslog Collection**: Accepts logs via UDP/TCP on port 514
- **Web Interface**: Simple dashboard for browsing and downloading logs
- **Basic Authentication**: Configurable password protection
- **Docker-based**: Uses rsyslog container for reliable log collection
- **File Downloads**: Direct download of collected log files
- **Self-contained**: Complete VPC setup, no external dependencies

## Quick Start

1. **Prerequisites**:
   - AWS CLI configured with appropriate permissions
   - Terraform installed
   - An existing EC2 Key Pair in your AWS region

2. **Configure Variables**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your settings
   ```

3. **Deploy**:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. **Access**:
   - Web UI: `http://<public-ip>` (username: `admin`, password: as configured)
   - Syslog endpoint: `<public-ip>:514` (UDP/TCP)
   - SSH: `ssh -i ~/.ssh/your-key.pem ec2-user@<public-ip>`

## Configuration

### Required Variables

- `ssh_key_name`: Name of your AWS EC2 Key Pair
- `web_ui_password`: Password for the web UI

### Optional Variables

- `aws_region`: AWS region (default: us-east-2)
- `instance_type`: EC2 instance type (default: t3.small)
- `vpc_cidr`: VPC CIDR block (default: 10.0.0.0/16)
- `ssh_allowed_cidrs`: IPs allowed SSH access (default: 0.0.0.0/0)
- `web_ui_allowed_cidrs`: IPs allowed web UI access (default: 0.0.0.0/0)

## Usage Examples

### Send Test Logs

```bash
# Using logger command
logger -n <public-ip> -P 514 "Test message from $(hostname)"

# Using Python
python3 -c "
import logging.handlers
import sys
handler = logging.handlers.SysLogHandler(address=('$PUBLIC_IP', 514))
logger = logging.getLogger('test')
logger.addHandler(handler)
logger.info('Test log message from Python')
"

# Using netcat
echo "Test syslog message" | nc -u <public-ip> 514
```

### Configure rsyslog to Forward Logs

Add to `/etc/rsyslog.conf` on source systems:
```
# Forward all logs to collector
*.* @@<public-ip>:514
```

### Download Logs

1. **Via Web UI**: Visit `http://<public-ip>` and click "Download All Logs"
2. **Via SSH**: 
   ```bash
   ssh -i ~/.ssh/your-key.pem ec2-user@<public-ip>
   sudo docker exec syslog-collector cat /var/log/collected-logs.log > collected-logs.txt
   scp -i ~/.ssh/your-key.pem ec2-user@<public-ip>:~/collected-logs.txt .
   ```

## File Structure

```
test-tools/syslog-collector/
├── main.tf                    # Main Terraform configuration
├── variables.tf               # Variable definitions
├── outputs.tf                 # Output definitions
├── user_data.sh              # EC2 instance initialization script
├── terraform.tfvars.example  # Example variables file
└── README.md                 # This file
```

## Outputs

After deployment, Terraform provides:
- `public_ip`: Public IP address of the collector
- `web_ui_url`: Direct URL to the web interface
- `syslog_endpoint`: Syslog endpoint for configuration
- `ssh_command`: SSH command to connect to the instance

## Security Notes

1. **Change default password**: Update `web_ui_password` in terraform.tfvars
2. **Restrict access**: Set `ssh_allowed_cidrs` and `web_ui_allowed_cidrs` to your IP ranges
3. **Use strong SSH keys**: Ensure your EC2 key pair is secure
4. **Monitor usage**: This is intended for testing; monitor for unexpected traffic

## Troubleshooting

### Check Services
```bash
# SSH to instance
ssh -i ~/.ssh/your-key.pem ec2-user@<public-ip>

# Check Docker containers
sudo docker ps

# Check logs
sudo docker logs syslog-collector
sudo docker logs syslog-web-ui

# Check if syslog is receiving data
sudo docker exec syslog-collector tail -f /var/log/collected-logs.log
```

### Test Connectivity
```bash
# Test UDP syslog
nc -u <public-ip> 514 <<< "Test UDP message"

# Test TCP syslog  
nc <public-ip> 514 <<< "Test TCP message"

# Test web UI
curl -u admin:your-password http://<public-ip>
```

## Cleanup

```bash
terraform destroy
```

This will remove all created AWS resources.

## Cost Estimation

- t3.small instance: ~$15-20/month
- EBS storage (20GB): ~$2/month
- Data transfer: Varies based on usage
- Other resources: <$5/month

Total estimated cost: ~$20-25/month for continuous operation.

## Integration with Log Integration Engine

The collected logs can be used to test your log integration engine:

1. **Collect logs** for a day or desired duration
2. **Download** the collected log file via web UI or SSH
3. **Use as input** for testing logstash configurations
4. **Validate parsing** and transformation rules

This provides a controlled source of real syslog data for testing and development.
