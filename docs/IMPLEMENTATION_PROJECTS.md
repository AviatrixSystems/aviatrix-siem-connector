# Implementation Projects

This document contains detailed instructions for implementing three separate projects to enhance the Aviatrix Log Integration Engine.

---

## Project 1: Modularize Logstash Configuration

### Objective
Refactor the repository to support modular Logstash configuration files, eliminating duplication across output configs and enabling mix-and-match filter/output combinations.

### Current State
- Monolithic config files: Each output config (`output_splunk_hec/`, `output_azure_log_ingestion_api/`) contains duplicated input and filter blocks
- ~400 lines of filter logic duplicated across 3+ config files
- Changes to parsing logic require updates in multiple places
- Pattern file (`base_config/patterns/avx.conf`) is minimal and underutilized

### Target State
```
logstash-configs/
├── inputs/
│   └── 00-syslog-input.conf           # Shared UDP/TCP 5000 input
├── filters/
│   ├── 10-fqdn.conf                   # FQDN rule parsing
│   ├── 11-cmd.conf                    # Controller CMD/API parsing
│   ├── 12-microseg.conf               # L4 microseg parsing (legacy + 8.2)
│   ├── 13-l7-dcf.conf                 # L7 DCF/MITM parsing (legacy + 8.2)
│   ├── 14-suricata.conf               # Suricata IDS parsing
│   ├── 15-gateway-stats.conf          # gw_net_stats, gw_sys_stats
│   ├── 16-tunnel-status.conf          # Tunnel state changes
│   ├── 80-throttle.conf               # Microseg throttling
│   ├── 90-timestamp.conf              # Date normalization
│   └── 95-field-conversion.conf       # Type conversions
├── outputs/
│   ├── splunk-hec/
│   │   ├── output.conf                # Splunk HEC output block only
│   │   └── docker_run.tftpl           # Docker run template
│   ├── azure-log-ingestion/
│   │   ├── output.conf                # Azure Log Ingestion output block only
│   │   └── docker_run.tftpl
│   └── elasticsearch/
│       └── output.conf                # ES output (from origin_logstash.conf)
├── patterns/
│   └── avx.conf                       # Enhanced grok patterns
├── assembled/                          # Pre-assembled configs for deployment
│   ├── splunk-hec-full.conf
│   ├── azure-lia-full.conf
│   └── elasticsearch-full.conf
└── scripts/
    └── assemble-config.sh             # Script to combine modules
```

### Implementation Steps

#### Step 1: Create Enhanced Pattern File
**File:** `logstash-configs/patterns/avx.conf`

Add these patterns to support both legacy and 8.2 log formats:
```
# Existing patterns
SYSLOG_TIMESTAMP (%{TIMESTAMP_ISO8601}|(%{MONTH} +%{MONTHDAY} +%{TIME}))
TUNNEL_GW %{NOTSPACE}(%{NOTSPACE} %{NOTSPACE})

# New patterns for 8.2
AVX_GATEWAY_HOST GW-%{HOSTNAME:gw_hostname}-%{IP:gw_ip}
AVX_MICROSEG_HEADER microseg:|AviatrixGwMicrosegPacket:
AVX_L7_HEADER ats_dcf:|traffic_server(\[%{NUMBER}\]:)?
AVX_SESSION_FIELDS (SESSION_EVENT=%{NUMBER:session_event} SESSION_END_REASON=%{NUMBER:session_end_reason} SESSION_PACKET_COUNT=%{NUMBER:session_packet_count} SESSION_BYTE_COUNT=%{NUMBER:session_byte_count} SESSION_DURATION=%{NUMBER:session_duration_ns})?
```

#### Step 2: Create Modular Input Config
**File:** `logstash-configs/inputs/00-syslog-input.conf`

```ruby
input {
    udp {
        port => 5000
        type => syslog
    }
    tcp {
        port => 5000
        type => syslog
    }
}
```

#### Step 3: Create Individual Filter Modules

Each filter module should:
1. Check `[type] == "syslog"`
2. Exclude already-tagged events
3. Add appropriate tags on match
4. Have a unique filter `id`

**Example - File:** `logstash-configs/filters/12-microseg.conf`

```ruby
# L4 Microseg Filter - Supports legacy and 8.2 formats
filter {
    if [type] == "syslog" and !("fqdn" in [tags] or "cmd" in [tags]) {
        grok {
            id => "microseg-grok"
            patterns_dir => ["/usr/share/logstash/patterns"]
            break_on_match => true
            add_tag => ["microseg", "l4"]
            remove_tag => ["_grokparsefailure"]
            match => {
                "message" => [
                    # 8.2 format with session fields
                    "^<%{NUMBER:syslog_pri}>%{SYSLOG_TIMESTAMP:date} %{HOSTNAME:gw_hostname} microseg: POLICY=%{UUID:policy_uuid} SRC_MAC=%{MAC:src_mac} DST_MAC=%{MAC:dst_mac} IP_SZ=%{NUMBER:ip_size} SRC_IP=%{IP:src_ip} DST_IP=%{IP:dst_ip} PROTO=%{WORD:proto} SRC_PORT=%{NUMBER:src_port} DST_PORT=%{NUMBER:dst_port} DATA=%{NOTSPACE} ACT=%{WORD:act} ENFORCED=%{WORD:enforced}( SESSION_EVENT=%{NUMBER:session_event} SESSION_END_REASON=%{NUMBER:session_end_reason} SESSION_PACKET_COUNT=%{NUMBER:packets} SESSION_BYTE_COUNT=%{NUMBER:bytes} SESSION_DURATION=%{NUMBER:duration_ns})?",

                    # Legacy 7.x format
                    "^<%{NUMBER}>%{SPACE}(%{MONTH} +%{MONTHDAY} +%{TIME} +%{HOSTNAME}-%{IP} syslog )?%{SYSLOG_TIMESTAMP:date} +GW-%{HOSTNAME:gw_hostname}-%{IP} +%{PATH}(\[%{NUMBER}\]:)? +%{YEAR}\/%{SPACE}%{MONTHNUM}\/%{SPACE}%{MONTHDAY} +%{TIME} +AviatrixGwMicrosegPacket: POLICY=%{UUID:policy_uuid} SRC_MAC=%{MAC:src_mac} DST_MAC=%{MAC:dst_mac} IP_SZ=%{NUMBER} SRC_IP=%{IP:src_ip} DST_IP=%{IP:dst_ip} PROTO=%{WORD:proto} SRC_PORT=%{NUMBER:src_port} DST_PORT=%{NUMBER:dst_port} DATA=%{GREEDYDATA} ACT=%{WORD:act} ENFORCED=%{WORD:enforced}"
                ]
            }
        }
    }
}
```

#### Step 4: Create Output-Only Modules

Each output module should contain ONLY the output block with conditional routing.

**Example - File:** `logstash-configs/outputs/splunk-hec/output.conf`

```ruby
output {
    if "suricata" in [tags] {
        http {
            id => "splunk-suricata"
            # ... splunk config
        }
    }
    else if "microseg" in [tags] {
        http {
            id => "splunk-microseg"
            # ... splunk config
        }
    }
    # ... other outputs
}
```

#### Step 5: Create Assembly Script
**File:** `logstash-configs/scripts/assemble-config.sh`

```bash
#!/bin/bash
# Assembles modular configs into a single deployable config file
# Usage: ./assemble-config.sh <output-type> <destination>
# Example: ./assemble-config.sh splunk-hec ./assembled/splunk-hec-full.conf

OUTPUT_TYPE=$1
DEST=$2
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")"

cat "$CONFIG_DIR/inputs/"*.conf > "$DEST"
cat "$CONFIG_DIR/filters/"*.conf >> "$DEST"
cat "$CONFIG_DIR/outputs/$OUTPUT_TYPE/output.conf" >> "$DEST"

echo "Assembled config written to $DEST"
```

#### Step 6: Update Terraform Deployments

Modify Terraform to upload multiple config files or the assembled config:

**Option A:** Upload assembled config (simpler)
- Run assembly script before `terraform apply`
- Upload single file to S3/Azure Storage

**Option B:** Upload individual modules (more flexible)
- Modify S3 upload to handle multiple files
- Update container volume mounts to include all config directories

#### Step 7: Update CLAUDE.md

Add documentation about the new modular structure.

### Acceptance Criteria
- [ ] All filter logic exists in exactly one place
- [ ] Adding a new output destination requires only creating a new output module
- [ ] Existing deployments continue to work with assembled configs
- [ ] Pattern file contains all custom patterns
- [ ] Assembly script can produce working configs for all output types
- [ ] Tests pass with assembled configs (if tests exist)

### Files to Create
1. `logstash-configs/inputs/00-syslog-input.conf`
2. `logstash-configs/filters/10-fqdn.conf`
3. `logstash-configs/filters/11-cmd.conf`
4. `logstash-configs/filters/12-microseg.conf`
5. `logstash-configs/filters/13-l7-dcf.conf`
6. `logstash-configs/filters/14-suricata.conf`
7. `logstash-configs/filters/15-gateway-stats.conf`
8. `logstash-configs/filters/16-tunnel-status.conf`
9. `logstash-configs/filters/80-throttle.conf`
10. `logstash-configs/filters/90-timestamp.conf`
11. `logstash-configs/filters/95-field-conversion.conf`
12. `logstash-configs/outputs/splunk-hec/output.conf`
13. `logstash-configs/outputs/azure-log-ingestion/output.conf`
14. `logstash-configs/scripts/assemble-config.sh`

### Files to Modify
1. `logstash-configs/patterns/avx.conf` - Enhance with new patterns
2. `deployment-tf/aws-ec2-single-instance/main.tf` - Update S3 upload logic
3. `deployment-tf/aws-ec2-autoscale/main.tf` - Update S3 upload logic
4. `CLAUDE.md` - Document new structure

### Files to Deprecate (keep for reference)
1. `logstash-configs/output_splunk_hec/logstash_output_splunk_hec.conf`
2. `logstash-configs/output_splunk_hec/logstash_output_splunk_hec_all.conf`
3. `logstash-configs/output_azure_log_ingestion_api/logstash_output_azure_lia.conf`

---

## Project 2: AWS ECS Deployment

### Objective
Create a new Terraform deployment that runs the Logstash log integration engine on AWS ECS (Fargate), providing a managed container experience without EC2 instance management.

### Architecture
```
┌─────────────────────────────────────────────────────────────────┐
│                         AWS Region                               │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                          VPC                               │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │              Public Subnet(s)                        │  │  │
│  │  │  ┌─────────────┐    ┌─────────────────────────────┐ │  │  │
│  │  │  │     NLB     │───▶│      ECS Service            │ │  │  │
│  │  │  │ (Elastic IP)│    │  ┌─────────────────────┐    │ │  │  │
│  │  │  │  TCP/UDP    │    │  │  Fargate Task       │    │ │  │  │
│  │  │  │  :5000      │    │  │  ┌───────────────┐  │    │ │  │  │
│  │  │  └─────────────┘    │  │  │   Logstash    │  │    │ │  │  │
│  │  │                     │  │  │   Container   │  │    │ │  │  │
│  │  │                     │  │  └───────────────┘  │    │ │  │  │
│  │  │                     │  └─────────────────────┘    │ │  │  │
│  │  │                     └─────────────────────────────┘ │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  │                                                            │  │
│  │  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐   │  │
│  │  │      S3      │   │  CloudWatch  │   │   Secrets    │   │  │
│  │  │   (Config)   │   │    (Logs)    │   │   Manager    │   │  │
│  │  └──────────────┘   └──────────────┘   └──────────────┘   │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Directory Structure
```
deployment-tf/
└── aws-ecs-fargate/
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    ├── ecs.tf
    ├── nlb.tf
    ├── iam.tf
    ├── s3.tf
    ├── secrets.tf
    ├── cloudwatch.tf
    ├── terraform.tfvars.sample
    └── README.md
```

### Implementation Steps

#### Step 1: Create Main Terraform Configuration
**File:** `deployment-tf/aws-ecs-fargate/main.tf`

```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

locals {
  name_prefix = "avx-log-${random_string.suffix.result}"
  common_tags = merge(var.tags, {
    Project   = "aviatrix-log-integration"
    ManagedBy = "terraform"
  })
}

data "aws_vpc" "selected" {
  id = var.vpc_id
}

data "aws_subnets" "selected" {
  filter {
    name   = "subnet-id"
    values = var.subnet_ids
  }
}
```

#### Step 2: Create ECS Cluster and Service
**File:** `deployment-tf/aws-ecs-fargate/ecs.tf`

```hcl
# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = local.common_tags
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = var.use_spot ? "FARGATE_SPOT" : "FARGATE"
  }
}

# Task Definition
resource "aws_ecs_task_definition" "logstash" {
  family                   = "${local.name_prefix}-logstash"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "logstash"
      image     = var.logstash_image
      essential = true

      portMappings = [
        {
          containerPort = 5000
          hostPort      = 5000
          protocol      = "tcp"
        },
        {
          containerPort = 5000
          hostPort      = 5000
          protocol      = "udp"
        }
      ]

      environment = [
        {
          name  = "XPACK_MONITORING_ENABLED"
          value = "false"
        },
        {
          name  = "CONFIG_RELOAD_AUTOMATIC"
          value = "true"
        },
        {
          name  = "CONFIG_RELOAD_INTERVAL"
          value = "30s"
        }
      ]

      secrets = [
        {
          name      = "SPLUNK_HEC_TOKEN"
          valueFrom = aws_secretsmanager_secret.splunk_hec_token.arn
        },
        {
          name      = "SPLUNK_ADDRESS"
          valueFrom = "${aws_secretsmanager_secret.splunk_config.arn}:address::"
        },
        {
          name      = "SPLUNK_PORT"
          valueFrom = "${aws_secretsmanager_secret.splunk_config.arn}:port::"
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "pipeline-config"
          containerPath = "/usr/share/logstash/pipeline"
          readOnly      = true
        },
        {
          sourceVolume  = "patterns"
          containerPath = "/usr/share/logstash/patterns"
          readOnly      = true
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.logstash.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "logstash"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:9600/ || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    },
    {
      name      = "config-sidecar"
      image     = "amazon/aws-cli:latest"
      essential = false

      command = [
        "/bin/sh", "-c",
        "aws s3 sync s3://${aws_s3_bucket.config.id}/pipeline/ /config/pipeline/ && aws s3 sync s3://${aws_s3_bucket.config.id}/patterns/ /config/patterns/ && sleep infinity"
      ]

      mountPoints = [
        {
          sourceVolume  = "pipeline-config"
          containerPath = "/config/pipeline"
          readOnly      = false
        },
        {
          sourceVolume  = "patterns"
          containerPath = "/config/patterns"
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.logstash.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "config-sync"
        }
      }
    }
  ])

  volume {
    name = "pipeline-config"
  }

  volume {
    name = "patterns"
  }

  tags = local.common_tags
}

# ECS Service
resource "aws_ecs_service" "logstash" {
  name            = "${local.name_prefix}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.logstash.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = var.assign_public_ip
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tcp.arn
    container_name   = "logstash"
    container_port   = 5000
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.udp.arn
    container_name   = "logstash"
    container_port   = 5000
  }

  deployment_configuration {
    maximum_percent         = 200
    minimum_healthy_percent = 100
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = local.common_tags

  lifecycle {
    ignore_changes = [desired_count]
  }
}

# Auto Scaling
resource "aws_appautoscaling_target" "ecs" {
  count              = var.enable_autoscaling ? 1 : 0
  max_capacity       = var.max_count
  min_capacity       = var.min_count
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.logstash.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  count              = var.enable_autoscaling ? 1 : 0
  name               = "${local.name_prefix}-cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.cpu_target_value
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# Security Group
resource "aws_security_group" "ecs_tasks" {
  name        = "${local.name_prefix}-ecs-tasks"
  description = "Security group for Logstash ECS tasks"
  vpc_id      = var.vpc_id

  ingress {
    description = "Syslog TCP"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {
    description = "Syslog UDP"
    from_port   = 5000
    to_port     = 5000
    protocol    = "udp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {
    description = "Logstash API (health check)"
    from_port   = 9600
    to_port     = 9600
    protocol    = "tcp"
    self        = true
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}
```

#### Step 3: Create Network Load Balancer
**File:** `deployment-tf/aws-ecs-fargate/nlb.tf`

```hcl
# Network Load Balancer
resource "aws_lb" "main" {
  name               = "${local.name_prefix}-nlb"
  internal           = var.internal_nlb
  load_balancer_type = "network"
  subnets            = var.subnet_ids

  enable_cross_zone_load_balancing = true

  tags = local.common_tags
}

# Elastic IP for NLB (if public)
resource "aws_eip" "nlb" {
  count  = var.internal_nlb ? 0 : length(var.subnet_ids)
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "${local.name_prefix}-nlb-eip-${count.index}" })
}

# TCP Target Group
resource "aws_lb_target_group" "tcp" {
  name        = "${local.name_prefix}-tcp"
  port        = 5000
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
    port                = "9600"
    protocol            = "TCP"
  }

  tags = local.common_tags
}

# UDP Target Group
resource "aws_lb_target_group" "udp" {
  name        = "${local.name_prefix}-udp"
  port        = 5000
  protocol    = "UDP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
    port                = "9600"
    protocol            = "TCP"
  }

  tags = local.common_tags
}

# TCP Listener
resource "aws_lb_listener" "tcp" {
  load_balancer_arn = aws_lb.main.arn
  port              = 5000
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tcp.arn
  }

  tags = local.common_tags
}

# UDP Listener
resource "aws_lb_listener" "udp" {
  load_balancer_arn = aws_lb.main.arn
  port              = 5000
  protocol          = "UDP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.udp.arn
  }

  tags = local.common_tags
}
```

#### Step 4: Create IAM Roles
**File:** `deployment-tf/aws-ecs-fargate/iam.tf`

```hcl
# ECS Task Execution Role
resource "aws_iam_role" "ecs_execution" {
  name = "${local.name_prefix}-ecs-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_execution_secrets" {
  name = "${local.name_prefix}-secrets-access"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue"
      ]
      Resource = [
        aws_secretsmanager_secret.splunk_hec_token.arn,
        aws_secretsmanager_secret.splunk_config.arn
      ]
    }]
  })
}

# ECS Task Role
resource "aws_iam_role" "ecs_task" {
  name = "${local.name_prefix}-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "ecs_task_s3" {
  name = "${local.name_prefix}-s3-access"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:ListBucket"
      ]
      Resource = [
        aws_s3_bucket.config.arn,
        "${aws_s3_bucket.config.arn}/*"
      ]
    }]
  })
}
```

#### Step 5: Create S3 Config Bucket
**File:** `deployment-tf/aws-ecs-fargate/s3.tf`

```hcl
# S3 Bucket for Logstash Config
resource "aws_s3_bucket" "config" {
  bucket = "${local.name_prefix}-config"
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "config" {
  bucket = aws_s3_bucket.config.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  bucket = aws_s3_bucket.config.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Upload Logstash pipeline config
resource "aws_s3_object" "pipeline_config" {
  bucket = aws_s3_bucket.config.id
  key    = "pipeline/logstash.conf"
  source = var.logstash_config_path
  etag   = filemd5(var.logstash_config_path)
  tags   = local.common_tags
}

# Upload patterns
resource "aws_s3_object" "patterns" {
  bucket = aws_s3_bucket.config.id
  key    = "patterns/avx.conf"
  source = var.patterns_config_path
  etag   = filemd5(var.patterns_config_path)
  tags   = local.common_tags
}
```

#### Step 6: Create Secrets Manager Resources
**File:** `deployment-tf/aws-ecs-fargate/secrets.tf`

```hcl
# Splunk HEC Token
resource "aws_secretsmanager_secret" "splunk_hec_token" {
  name        = "${local.name_prefix}/splunk-hec-token"
  description = "Splunk HEC authentication token"
  tags        = local.common_tags
}

resource "aws_secretsmanager_secret_version" "splunk_hec_token" {
  secret_id     = aws_secretsmanager_secret.splunk_hec_token.id
  secret_string = var.splunk_hec_token
}

# Splunk Config
resource "aws_secretsmanager_secret" "splunk_config" {
  name        = "${local.name_prefix}/splunk-config"
  description = "Splunk connection configuration"
  tags        = local.common_tags
}

resource "aws_secretsmanager_secret_version" "splunk_config" {
  secret_id = aws_secretsmanager_secret.splunk_config.id
  secret_string = jsonencode({
    address = var.splunk_address
    port    = var.splunk_port
  })
}
```

#### Step 7: Create CloudWatch Resources
**File:** `deployment-tf/aws-ecs-fargate/cloudwatch.tf`

```hcl
# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "logstash" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${local.name_prefix}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "ECS CPU utilization high"

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.logstash.name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "memory_high" {
  alarm_name          = "${local.name_prefix}-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "ECS memory utilization high"

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.logstash.name
  }

  tags = local.common_tags
}
```

#### Step 8: Create Variables
**File:** `deployment-tf/aws-ecs-fargate/variables.tf`

```hcl
variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for ECS tasks"
  type        = list(string)
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}

# ECS Configuration
variable "logstash_image" {
  description = "Logstash Docker image"
  type        = string
  default     = "docker.elastic.co/logstash/logstash:8.16.2"
}

variable "task_cpu" {
  description = "Fargate task CPU units"
  type        = number
  default     = 1024  # 1 vCPU
}

variable "task_memory" {
  description = "Fargate task memory (MB)"
  type        = number
  default     = 2048  # 2 GB
}

variable "desired_count" {
  description = "Desired number of tasks"
  type        = number
  default     = 2
}

variable "use_spot" {
  description = "Use Fargate Spot capacity"
  type        = bool
  default     = false
}

variable "assign_public_ip" {
  description = "Assign public IP to tasks"
  type        = bool
  default     = true
}

# Autoscaling
variable "enable_autoscaling" {
  description = "Enable ECS service autoscaling"
  type        = bool
  default     = true
}

variable "min_count" {
  description = "Minimum task count"
  type        = number
  default     = 1
}

variable "max_count" {
  description = "Maximum task count"
  type        = number
  default     = 4
}

variable "cpu_target_value" {
  description = "Target CPU utilization for autoscaling"
  type        = number
  default     = 70
}

# Network
variable "internal_nlb" {
  description = "Create internal NLB"
  type        = bool
  default     = false
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to send syslog"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Splunk Configuration
variable "splunk_address" {
  description = "Splunk HEC hostname"
  type        = string
}

variable "splunk_port" {
  description = "Splunk HEC port"
  type        = string
  default     = "8088"
}

variable "splunk_hec_token" {
  description = "Splunk HEC token"
  type        = string
  sensitive   = true
}

# Logstash Configuration
variable "logstash_config_path" {
  description = "Path to Logstash pipeline config"
  type        = string
  default     = "../../logstash-configs/assembled/splunk-hec-cim-full.conf"
}

variable "patterns_config_path" {
  description = "Path to patterns config"
  type        = string
  default     = "../../logstash-configs/patterns/avx.conf"
}

# Monitoring
variable "enable_container_insights" {
  description = "Enable ECS Container Insights"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}
```

#### Step 9: Create Outputs
**File:** `deployment-tf/aws-ecs-fargate/outputs.tf`

```hcl
output "nlb_dns_name" {
  description = "NLB DNS name for syslog destination"
  value       = aws_lb.main.dns_name
}

output "nlb_arn" {
  description = "NLB ARN"
  value       = aws_lb.main.arn
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.logstash.name
}

output "config_bucket" {
  description = "S3 bucket for Logstash configuration"
  value       = aws_s3_bucket.config.id
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group for Logstash"
  value       = aws_cloudwatch_log_group.logstash.name
}

output "syslog_endpoint" {
  description = "Syslog endpoint for Aviatrix configuration"
  value       = "${aws_lb.main.dns_name}:5000"
}
```

#### Step 10: Create Sample Variables File
**File:** `deployment-tf/aws-ecs-fargate/terraform.tfvars.sample`

```hcl
aws_region = "us-west-2"
vpc_id     = "vpc-xxxxxxxxx"
subnet_ids = ["subnet-xxxxxx", "subnet-yyyyyy"]

tags = {
  Environment = "production"
  Application = "aviatrix-logging"
}

# ECS Configuration
task_cpu      = 1024
task_memory   = 2048
desired_count = 2

# Autoscaling
enable_autoscaling = true
min_count          = 1
max_count          = 4
cpu_target_value   = 70

# Splunk Configuration
splunk_address   = "splunk.example.com"
splunk_port      = "8088"
splunk_hec_token = "your-hec-token-here"

# Logstash Configuration
logstash_config_path = "../../logstash-configs/assembled/splunk-hec-cim-full.conf"
patterns_config_path = "../../logstash-configs/patterns/avx.conf"
```

### Acceptance Criteria
- [ ] ECS Fargate cluster deploys successfully
- [ ] Tasks receive syslog on port 5000 (TCP and UDP)
- [ ] NLB provides stable endpoint for Aviatrix configuration
- [ ] Secrets are stored in AWS Secrets Manager (not environment variables)
- [ ] Config changes in S3 are picked up by running tasks
- [ ] CloudWatch logs capture Logstash output
- [ ] Autoscaling responds to CPU utilization
- [ ] Health checks properly detect unhealthy tasks
- [ ] Deployment includes README with usage instructions

### Files to Create
1. `deployment-tf/aws-ecs-fargate/main.tf`
2. `deployment-tf/aws-ecs-fargate/variables.tf`
3. `deployment-tf/aws-ecs-fargate/outputs.tf`
4. `deployment-tf/aws-ecs-fargate/ecs.tf`
5. `deployment-tf/aws-ecs-fargate/nlb.tf`
6. `deployment-tf/aws-ecs-fargate/iam.tf`
7. `deployment-tf/aws-ecs-fargate/s3.tf`
8. `deployment-tf/aws-ecs-fargate/secrets.tf`
9. `deployment-tf/aws-ecs-fargate/cloudwatch.tf`
10. `deployment-tf/aws-ecs-fargate/terraform.tfvars.sample`
11. `deployment-tf/aws-ecs-fargate/README.md`

---

## Dependencies Between Projects

```
Project 1 (Modularization) ✅ COMPLETED
         │
         ▼
Project 2 (AWS ECS) ──depends on──▶ Assembled config files
```

**Implementation Status:**
1. ✅ **Project 1** - Modularization complete
2. **Project 2** - AWS ECS deployment (can be implemented now)
