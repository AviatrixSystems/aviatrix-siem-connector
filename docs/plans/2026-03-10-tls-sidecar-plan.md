# TLS Sidecar Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add optional mTLS syslog ingestion (port 6514) via a stunnel sidecar container, with Terraform-managed certificate lifecycle and AWS Secrets Manager integration.

**Architecture:** A stunnel sidecar container terminates mTLS on port 6514 and forwards plaintext TCP to Logstash on localhost:5000. Terraform generates CA + server + client certs, stores them in Secrets Manager, and optionally configures the Aviatrix controller. The sidecar is conditionally deployed when `tls_enabled = true`.

**Tech Stack:** stunnel (Alpine), Terraform `tls` provider, AWS Secrets Manager, Docker Compose (EC2), ECS Fargate multi-container tasks.

**Design doc:** `docs/plans/2026-03-10-tls-sidecar-design.md`

---

### Task 1: Create stunnel sidecar container image

**Files:**
- Create: `tls-sidecar/Dockerfile`
- Create: `tls-sidecar/entrypoint.sh`
- Create: `tls-sidecar/build.sh`

**Step 1: Create the entrypoint script**

Create `tls-sidecar/entrypoint.sh`:

```bash
#!/bin/sh
set -e

CERT_DIR="/etc/stunnel/certs"
mkdir -p "$CERT_DIR"

# Write certs from env vars if set (ECS mode — secrets injected as env vars)
# If files already exist at CERT_DIR (volume mount mode — EC2), skip writing
if [ -n "$TLS_SERVER_CERT" ] && [ ! -f "$CERT_DIR/server.crt" ]; then
  echo "$TLS_SERVER_CERT" > "$CERT_DIR/server.crt"
  echo "$TLS_SERVER_KEY"  > "$CERT_DIR/server.key"
  echo "$TLS_CA_CERT"     > "$CERT_DIR/ca.crt"
fi

# Validate required cert files exist
for f in server.crt server.key ca.crt; do
  if [ ! -f "$CERT_DIR/$f" ]; then
    echo "ERROR: Missing $CERT_DIR/$f"
    echo "Provide certs via env vars (TLS_SERVER_CERT, TLS_SERVER_KEY, TLS_CA_CERT)"
    echo "or mount them as a volume at $CERT_DIR/"
    exit 1
  fi
done

chmod 600 "$CERT_DIR/server.key"

# Generate stunnel config
cat > /etc/stunnel/stunnel.conf <<EOF
foreground = yes
syslog = no

[syslog-tls]
accept = ${TLS_PORT:-6514}
connect = 127.0.0.1:${LOGSTASH_PORT:-5000}
cert = $CERT_DIR/server.crt
key = $CERT_DIR/server.key
CAfile = $CERT_DIR/ca.crt
verify = 2
EOF

echo "stunnel: listening on :${TLS_PORT:-6514} (mTLS) -> 127.0.0.1:${LOGSTASH_PORT:-5000}"
exec stunnel /etc/stunnel/stunnel.conf
```

**Step 2: Create the Dockerfile**

Create `tls-sidecar/Dockerfile`:

```dockerfile
FROM alpine:3.21
RUN apk add --no-cache stunnel
COPY --chmod=755 entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
```

**Step 3: Create the build script**

Create `tls-sidecar/build.sh`:

```bash
#!/usr/bin/env bash
# Build the TLS sidecar image locally
#
# Usage:
#   ./build.sh                    # Build with tag "local"
#   ./build.sh --tag v1.0.0       # Build with specific tag

set -euo pipefail

TAG="local"
IMAGE_NAME="ghcr.io/aviatrixsystems/siem-connector-tls"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) TAG="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--tag <tag>]"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if command -v docker &>/dev/null; then
  CONTAINER_CMD="docker"
elif command -v podman &>/dev/null; then
  CONTAINER_CMD="podman"
else
  echo "Error: neither docker nor podman found"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

$CONTAINER_CMD build \
  --platform linux/amd64 \
  -t "$IMAGE_NAME:$TAG" \
  "$SCRIPT_DIR"

echo ""
echo "Done! Image built: $IMAGE_NAME:$TAG"
```

**Step 4: Build and test the sidecar image locally**

```bash
cd tls-sidecar && chmod +x build.sh entrypoint.sh && ./build.sh
```

Expected: image builds successfully (~8MB).

**Step 5: Verify stunnel starts with test certs**

Generate throwaway test certs and verify the container starts:

```bash
# Generate test CA + server cert
mkdir -p /tmp/tls-test-certs
openssl req -x509 -newkey rsa:2048 -keyout /tmp/tls-test-certs/ca.key \
  -out /tmp/tls-test-certs/ca.crt -days 1 -nodes -subj "/CN=Test CA"
openssl req -newkey rsa:2048 -keyout /tmp/tls-test-certs/server.key \
  -out /tmp/tls-test-certs/server.csr -nodes -subj "/CN=localhost"
openssl x509 -req -in /tmp/tls-test-certs/server.csr \
  -CA /tmp/tls-test-certs/ca.crt -CAkey /tmp/tls-test-certs/ca.key \
  -CAcreateserial -out /tmp/tls-test-certs/server.crt -days 1

# Run sidecar (will fail to connect to logstash but should START successfully)
docker run --rm --name stunnel-test \
  -v /tmp/tls-test-certs:/etc/stunnel/certs:ro \
  -p 6514:6514 \
  ghcr.io/aviatrixsystems/siem-connector-tls:local &

sleep 2
# Verify it's listening
docker logs stunnel-test 2>&1 | grep "listening on :6514"
docker stop stunnel-test
rm -rf /tmp/tls-test-certs
```

Expected: "stunnel: listening on :6514 (mTLS) -> 127.0.0.1:5000"

**Step 6: Commit**

```bash
git add tls-sidecar/
git commit -m "feat: add stunnel TLS sidecar container image"
```

---

### Task 2: Create TLS certificate Terraform module

**Files:**
- Create: `deployments/modules/tls-certs/main.tf`
- Create: `deployments/modules/tls-certs/variables.tf`
- Create: `deployments/modules/tls-certs/outputs.tf`

**Step 1: Create variables.tf**

Create `deployments/modules/tls-certs/variables.tf`:

```hcl
variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "cert_validity_hours" {
  description = "Validity period for server and client certs (CA is 10x)"
  type        = number
  default     = 8760 # 1 year
}

variable "server_common_name" {
  description = "Common name for the server certificate"
  type        = string
  default     = "siem-connector"
}

variable "server_dns_names" {
  description = "DNS SANs for the server certificate (e.g., NLB DNS name)"
  type        = list(string)
  default     = []
}

variable "server_ip_addresses" {
  description = "IP SANs for the server certificate"
  type        = list(string)
  default     = []
}

variable "organization" {
  description = "Organization name for certificate subjects"
  type        = string
  default     = "Aviatrix SIEM Connector"
}

variable "secret_name" {
  description = "Secrets Manager secret name. Auto-generated if empty."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
```

**Step 2: Create main.tf (cert generation + secrets)**

Create `deployments/modules/tls-certs/main.tf`:

```hcl
# --- Certificate Authority (long-lived) ---

resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem = tls_private_key.ca.private_key_pem

  subject {
    common_name  = "${var.name_prefix} CA"
    organization = var.organization
  }

  validity_period_hours = var.cert_validity_hours * 10 # 10x server cert lifetime
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

# --- Server Certificate (presented by stunnel sidecar) ---

resource "tls_private_key" "server" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "server" {
  private_key_pem = tls_private_key.server.private_key_pem

  subject {
    common_name  = var.server_common_name
    organization = var.organization
  }

  dns_names    = var.server_dns_names
  ip_addresses = var.server_ip_addresses
}

resource "tls_locally_signed_cert" "server" {
  cert_request_pem   = tls_cert_request.server.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = var.cert_validity_hours

  allowed_uses = [
    "server_auth",
    "digital_signature",
    "key_encipherment",
  ]
}

# --- Client Certificate (presented by Aviatrix gateways) ---

resource "tls_private_key" "client" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "client" {
  private_key_pem = tls_private_key.client.private_key_pem

  subject {
    common_name  = "${var.name_prefix} Client"
    organization = var.organization
  }
}

resource "tls_locally_signed_cert" "client" {
  cert_request_pem   = tls_cert_request.client.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = var.cert_validity_hours

  allowed_uses = [
    "client_auth",
    "digital_signature",
    "key_encipherment",
  ]
}

# --- AWS Secrets Manager (server-side certs for stunnel) ---

resource "aws_secretsmanager_secret" "tls" {
  name        = var.secret_name != "" ? var.secret_name : "${var.name_prefix}-tls-certs"
  description = "TLS certificates for SIEM connector mTLS sidecar"
  tags        = var.tags
}

resource "aws_secretsmanager_secret_version" "tls" {
  secret_id = aws_secretsmanager_secret.tls.id
  secret_string = jsonencode({
    server_cert = tls_locally_signed_cert.server.cert_pem
    server_key  = tls_private_key.server.private_key_pem
    ca_cert     = tls_self_signed_cert.ca.cert_pem
  })
}
```

**Step 3: Create outputs.tf**

Create `deployments/modules/tls-certs/outputs.tf`:

```hcl
output "secret_arn" {
  description = "ARN of the Secrets Manager secret containing server certs"
  value       = aws_secretsmanager_secret.tls.arn
}

output "ca_cert_pem" {
  description = "CA certificate PEM — upload to Aviatrix as 'Server CA Certificate'"
  value       = tls_self_signed_cert.ca.cert_pem
  sensitive   = true
}

output "client_cert_pem" {
  description = "Client certificate PEM — upload to Aviatrix as 'Client Certificate'"
  value       = tls_locally_signed_cert.client.cert_pem
  sensitive   = true
}

output "client_key_pem" {
  description = "Client private key PEM — upload to Aviatrix as 'Client Private Key'"
  value       = tls_private_key.client.private_key_pem
  sensitive   = true
}
```

**Step 4: Validate the module**

```bash
cd deployments/modules/tls-certs
terraform init
terraform validate
```

Expected: "Success! The configuration is valid."

**Step 5: Commit**

```bash
git add deployments/modules/tls-certs/
git commit -m "feat: add tls-certs Terraform module for mTLS cert generation"
```

---

### Task 3: ECS Fargate TLS integration

**Files:**
- Modify: `deployments/aws-ecs-fargate/variables.tf` (add TLS variables)
- Modify: `deployments/aws-ecs-fargate/providers.tf` (add `tls` provider)
- Create: `deployments/aws-ecs-fargate/tls.tf` (call tls-certs module)
- Modify: `deployments/aws-ecs-fargate/iam.tf` (Secrets Manager read policy)
- Modify: `deployments/aws-ecs-fargate/main.tf` (conditional stunnel container + port changes)
- Modify: `deployments/aws-ecs-fargate/nlb.tf` (conditional port/protocol)
- Modify: `deployments/aws-ecs-fargate/security-groups.tf` (conditional port rules)
- Modify: `deployments/aws-ecs-fargate/outputs.tf` (TLS outputs)

**Step 1: Add TLS variables**

Append to `deployments/aws-ecs-fargate/variables.tf` (after line 87):

```hcl
# --- TLS Configuration ---

variable "tls_enabled" {
  description = "Enable mTLS syslog ingestion via stunnel sidecar (port 6514 replaces plaintext port 5000)"
  type        = bool
  default     = false
}

variable "tls_port" {
  description = "TLS syslog port (RFC 5425 default: 6514)"
  type        = number
  default     = 6514
}

variable "tls_cert_validity_hours" {
  description = "Server/client certificate validity period in hours. CA validity is 10x this value."
  type        = number
  default     = 8760
}

variable "tls_secret_name" {
  description = "Secrets Manager secret name for TLS certs. Auto-generated if empty."
  type        = string
  default     = ""
}

variable "tls_sidecar_image" {
  description = "Container image for the TLS stunnel sidecar"
  type        = string
  default     = "ghcr.io/aviatrixsystems/siem-connector-tls:latest"
}

variable "tls_server_dns_names" {
  description = "DNS SANs for the server certificate (NLB DNS name is added automatically)"
  type        = list(string)
  default     = []
}
```

**Step 2: Add `tls` provider requirement**

Modify `deployments/aws-ecs-fargate/providers.tf` — add `tls` and `hashicorp/tls` to required_providers:

```hcl
terraform {
  required_version = ">= 1.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
```

**Step 3: Create tls.tf**

Create `deployments/aws-ecs-fargate/tls.tf`:

```hcl
# --- TLS Certificate Generation (conditional) ---
# Remove this file when migrating to controller-managed certs.

module "tls" {
  count  = var.tls_enabled ? 1 : 0
  source = "../modules/tls-certs"

  name_prefix     = local.name_prefix
  cert_validity_hours = var.tls_cert_validity_hours
  secret_name     = var.tls_secret_name
  server_dns_names = concat(
    [aws_lb.default.dns_name],
    var.tls_server_dns_names,
  )
  tags = var.tags
}
```

**Step 4: Add Secrets Manager read permission to IAM**

Modify `deployments/aws-ecs-fargate/iam.tf` — add a conditional policy for Secrets Manager access. Append after line 44 (after `aws_iam_role.ecs_task`):

```hcl
# --- Secrets Manager access for TLS certs (conditional) ---

resource "aws_iam_policy" "ecs_secrets" {
  count = var.tls_enabled ? 1 : 0

  name = "${local.name_prefix}-ecs-secrets"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = module.tls[0].secret_arn
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_secrets" {
  count = var.tls_enabled ? 1 : 0

  role       = aws_iam_role.ecs_execution.name
  policy_arn = aws_iam_policy.ecs_secrets[0].arn
}
```

**Step 5: Add local for effective syslog port and modify task definition**

Modify `deployments/aws-ecs-fargate/main.tf`.

Add a local for the effective port (after `local.name_prefix`, line 8):

```hcl
locals {
  name_prefix    = "avxlog-${random_string.suffix.result}"
  effective_port = var.tls_enabled ? var.tls_port : var.syslog_port
}
```

Replace the `container_definitions` block (lines 91-110) with a conditional that includes the stunnel sidecar when TLS is enabled:

```hcl
  container_definitions = jsonencode(concat(
    # --- stunnel TLS sidecar (conditional) ---
    var.tls_enabled ? [{
      name      = "stunnel"
      image     = var.tls_sidecar_image
      essential = true

      portMappings = [
        { containerPort = var.tls_port, protocol = "tcp" },
      ]

      environment = [
        { name = "TLS_PORT", value = tostring(var.tls_port) },
        { name = "LOGSTASH_PORT", value = tostring(var.syslog_port) },
      ]

      secrets = [
        { name = "TLS_SERVER_CERT", valueFrom = "${module.tls[0].secret_arn}:server_cert::" },
        { name = "TLS_SERVER_KEY", valueFrom = "${module.tls[0].secret_arn}:server_key::" },
        { name = "TLS_CA_CERT", valueFrom = "${module.tls[0].secret_arn}:ca_cert::" },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.default.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "stunnel"
        }
      }
    }] : [],

    # --- Logstash container (always present) ---
    [{
      name      = "logstash"
      image     = var.container_image
      essential = true

      portMappings = var.tls_enabled ? [] : [
        { containerPort = var.syslog_port, protocol = "tcp" },
      ]

      environment = local.container_env

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.default.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "logstash"
        }
      }
    }],
  ))
```

Update the `load_balancer` block in `aws_ecs_service` (lines 140-144) to use the stunnel container when TLS is on:

```hcl
  load_balancer {
    target_group_arn = aws_lb_target_group.default.arn
    container_name   = var.tls_enabled ? "stunnel" : "logstash"
    container_port   = local.effective_port
  }
```

**Step 6: Modify NLB for conditional port/protocol**

Replace `deployments/aws-ecs-fargate/nlb.tf` target group and listener (lines 18-49):

```hcl
# --- Target Group ---
# When TLS is enabled: TCP on 6514 (stunnel handles TLS, UDP not available)
# When TLS is disabled: TCP_UDP on syslog_port (current behavior)

resource "aws_lb_target_group" "default" {
  name        = local.name_prefix
  port        = local.effective_port
  protocol    = var.tls_enabled ? "TCP" : "TCP_UDP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    protocol            = "TCP"
    port                = "traffic-port"
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = var.tags
}

# --- Listener ---

resource "aws_lb_listener" "default" {
  load_balancer_arn = aws_lb.default.arn
  port              = local.effective_port
  protocol          = var.tls_enabled ? "TCP" : "TCP_UDP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.default.arn
  }

  tags = var.tags
}
```

**Step 7: Modify security groups for conditional port rules**

Replace `deployments/aws-ecs-fargate/security-groups.tf` ingress rules (lines 8-24):

```hcl
  # Syslog TCP
  ingress {
    description = var.tls_enabled ? "Syslog TLS" : "Syslog TCP"
    from_port   = local.effective_port
    to_port     = local.effective_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Syslog UDP — only when TLS is disabled (TLS is TCP-only)
  dynamic "ingress" {
    for_each = var.tls_enabled ? [] : [1]
    content {
      description = "Syslog UDP"
      from_port   = var.syslog_port
      to_port     = var.syslog_port
      protocol    = "udp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
```

**Step 8: Add TLS outputs**

Append to `deployments/aws-ecs-fargate/outputs.tf` (after line 22):

```hcl
# --- TLS Outputs ---

output "syslog_endpoint" {
  description = "Syslog destination — configure in Aviatrix controller"
  value       = "${aws_lb.default.dns_name}:${local.effective_port}"
}

output "syslog_protocol" {
  description = "Syslog transport protocol"
  value       = var.tls_enabled ? "TCP+TLS (mTLS)" : "UDP/TCP"
}

output "tls_ca_certificate_pem" {
  description = "CA cert PEM — upload to Aviatrix as 'Server CA Certificate'"
  value       = var.tls_enabled ? module.tls[0].ca_cert_pem : null
  sensitive   = true
}

output "tls_client_certificate_pem" {
  description = "Client cert PEM — upload to Aviatrix as 'Client Certificate'"
  value       = var.tls_enabled ? module.tls[0].client_cert_pem : null
  sensitive   = true
}

output "tls_client_private_key_pem" {
  description = "Client key PEM — upload to Aviatrix as 'Client Private Key'"
  value       = var.tls_enabled ? module.tls[0].client_key_pem : null
  sensitive   = true
}
```

**Step 9: Validate**

```bash
cd deployments/aws-ecs-fargate
terraform init -upgrade
terraform validate
```

Expected: "Success! The configuration is valid."

**Step 10: Commit**

```bash
git add deployments/aws-ecs-fargate/ deployments/modules/tls-certs/
git commit -m "feat: add conditional TLS sidecar to ECS Fargate deployment"
```

---

### Task 4: EC2 shared module TLS integration

**Files:**
- Modify: `deployments/modules/aws-logstash/variables.tf` (add TLS variables)
- Modify: `deployments/modules/aws-logstash/main.tf` (conditional SG port, user_data, IAM)
- Modify: `deployments/modules/aws-logstash/logstash_instance_init.tftpl` (conditional cert fetch)
- Create: `deployments/modules/aws-logstash/docker-compose.tftpl` (TLS compose template)
- Modify: `deployments/modules/aws-logstash/outputs.tf` (add effective port output)

**Step 1: Add TLS variables to shared module**

Append to `deployments/modules/aws-logstash/variables.tf` (after line 84):

```hcl
# --- TLS Configuration ---

variable "tls_enabled" {
  description = "Enable mTLS syslog ingestion via stunnel sidecar"
  type        = bool
  default     = false
}

variable "tls_port" {
  description = "TLS syslog port (RFC 5425 default: 6514)"
  type        = number
  default     = 6514
}

variable "tls_secret_arn" {
  description = "ARN of the Secrets Manager secret containing TLS certs"
  type        = string
  default     = ""
}

variable "tls_sidecar_image" {
  description = "Container image for the stunnel TLS sidecar"
  type        = string
  default     = "ghcr.io/aviatrixsystems/siem-connector-tls:latest"
}

variable "aws_region" {
  description = "AWS region (needed for Secrets Manager fetch in user_data)"
  type        = string
  default     = "us-east-2"
}
```

**Step 2: Modify security group for conditional port**

Modify `deployments/modules/aws-logstash/main.tf` security group (lines 84-107). Replace the syslog ingress rule (lines 88-93):

```hcl
resource "aws_security_group" "default" {
  count  = var.use_existing_security_group ? 0 : 1
  name   = "avxlog-${lower(random_string.random.id)}"
  vpc_id = var.vpc_id
  ingress {
    from_port   = var.tls_enabled ? var.tls_port : var.syslog_port
    to_port     = var.tls_enabled ? var.tls_port : var.syslog_port
    protocol    = var.tls_enabled ? "tcp" : var.syslog_protocol
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = "22"
    to_port     = "22"
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = var.tags
}
```

**Step 3: Add Secrets Manager read permission to IAM role**

Modify `deployments/modules/aws-logstash/main.tf`. Add a conditional IAM policy for Secrets Manager access after the existing `s3_read_policy` (after line 52):

```hcl
resource "aws_iam_policy" "secrets_read_policy" {
  count       = var.tls_enabled ? 1 : 0
  name        = "avxlog-secrets-${lower(random_string.random.id)}"
  description = "Policy to allow EC2 instances to read TLS certs from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action   = "secretsmanager:GetSecretValue",
      Effect   = "Allow",
      Resource = var.tls_secret_arn
    }],
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "secrets_read_attach" {
  count      = var.tls_enabled ? 1 : 0
  role       = aws_iam_role.ec2_s3_access_role.name
  policy_arn = aws_iam_policy.secrets_read_policy[0].arn
}
```

**Step 4: Modify user_data for conditional TLS mode**

Modify `deployments/modules/aws-logstash/main.tf` `locals.user_data` (lines 120-128):

```hcl
# User data: bootstrap script + docker run or docker-compose
locals {
  user_data = var.tls_enabled ? templatefile("${path.module}/logstash_instance_init.tftpl", {
    aws_s3_bucket_id     = aws_s3_bucket.default.id,
    logstash_config_name = aws_s3_object.config.key,
    tls_enabled          = true,
    tls_secret_arn       = var.tls_secret_arn,
    aws_region           = var.aws_region,
    tls_port             = var.tls_port,
    tls_sidecar_image    = var.tls_sidecar_image,
    log_profile          = var.log_profile,
    config_vars          = var.logstash_config_variables,
  }) : format("%s\n%s", templatefile("${path.module}/logstash_instance_init.tftpl", {
    aws_s3_bucket_id     = aws_s3_bucket.default.id,
    logstash_config_name = aws_s3_object.config.key,
    tls_enabled          = false,
    tls_secret_arn       = "",
    aws_region           = var.aws_region,
    tls_port             = 0,
    tls_sidecar_image    = "",
    log_profile          = "",
    config_vars          = {},
  }), templatefile(var.docker_run_template_path, merge(var.logstash_config_variables, {
    log_profile = var.log_profile
  })))
}
```

**Step 5: Update logstash_instance_init.tftpl**

Replace `deployments/modules/aws-logstash/logstash_instance_init.tftpl`:

```bash
#!/bin/bash
# STANDARD INIT FOR AVIATRIX SIEM CONNECTOR (AL2023)
set -e  # Exit on error

# Install packages
sudo yum update -y
sudo yum install -y docker aws-cli jq

# Start Docker
sudo systemctl start docker
sudo systemctl enable docker

# Create directories
mkdir -p /logstash/pipeline
mkdir -p /logstash/patterns

# Download config files from S3
aws s3 cp s3://${aws_s3_bucket_id}/avx.conf /logstash/patterns/avx.conf
aws s3 cp s3://${aws_s3_bucket_id}/${logstash_config_name} /logstash/pipeline/${logstash_config_name}

# Set proper permissions
chmod 644 /logstash/patterns/avx.conf
chmod 644 /logstash/pipeline/${logstash_config_name}

%{ if tls_enabled }
# --- TLS: Fetch certs from Secrets Manager ---
mkdir -p /logstash/certs

SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "${tls_secret_arn}" \
  --query 'SecretString' \
  --output text \
  --region "${aws_region}")

echo "$SECRET_JSON" | jq -r '.server_cert' > /logstash/certs/server.crt
echo "$SECRET_JSON" | jq -r '.server_key'  > /logstash/certs/server.key
echo "$SECRET_JSON" | jq -r '.ca_cert'     > /logstash/certs/ca.crt
chmod 600 /logstash/certs/server.key

# --- TLS: Write docker-compose.yml ---
cat > /logstash/docker-compose.yml <<'COMPOSE'
services:
  stunnel:
    image: ${tls_sidecar_image}
    ports:
      - "${tls_port}:${tls_port}"
    volumes:
      - /logstash/certs:/etc/stunnel/certs:ro
    environment:
      - TLS_PORT=${tls_port}
    restart: always
    depends_on:
      - logstash

  logstash:
    image: docker.elastic.co/logstash/logstash:8.16.2
    volumes:
      - /logstash/pipeline/:/usr/share/logstash/pipeline/
      - /logstash/patterns:/usr/share/logstash/patterns
    environment:
      - LOG_PROFILE=${log_profile}
      - XPACK_MONITORING_ENABLED=false
%{ for key, value in config_vars ~}
      - ${upper(key)}=${value}
%{ endfor ~}
    restart: always
COMPOSE

# --- TLS: Start with docker compose ---
cd /logstash
docker compose up -d
%{ endif }
```

Note: When `tls_enabled = false`, the script ends after S3 downloads and the non-TLS `docker_run.tftpl` is appended by the `format()` call in `locals.user_data`.

**Step 6: Add effective port output**

Append to `deployments/modules/aws-logstash/outputs.tf` (after line 39):

```hcl
output "effective_port" {
  description = "The externally-facing syslog port (TLS port when enabled, syslog port otherwise)"
  value       = var.tls_enabled ? var.tls_port : var.syslog_port
}
```

**Step 7: Validate**

```bash
cd deployments/modules/aws-logstash
terraform init
terraform validate
```

Expected: "Success! The configuration is valid." (module-level validation may warn about missing vars — that's fine for modules).

**Step 8: Commit**

```bash
git add deployments/modules/aws-logstash/
git commit -m "feat: add TLS support to shared aws-logstash module"
```

---

### Task 5: EC2 single-instance TLS wiring

**Files:**
- Modify: `deployments/aws-ec2-single-instance/variables.tf` (add TLS variables)
- Modify: `deployments/aws-ec2-single-instance/main.tf` (pass TLS vars to module)
- Create: `deployments/aws-ec2-single-instance/tls.tf` (call tls-certs module)
- Modify: `deployments/aws-ec2-single-instance/outputs.tf` (add TLS outputs, create if missing)

**Step 1: Add TLS variables**

Append to `deployments/aws-ec2-single-instance/variables.tf` (after line 75):

```hcl
# --- TLS Configuration ---

variable "tls_enabled" {
  description = "Enable mTLS syslog ingestion via stunnel sidecar (port 6514 replaces plaintext port 5000)"
  type        = bool
  default     = false
}

variable "tls_port" {
  description = "TLS syslog port (RFC 5425 default: 6514)"
  type        = number
  default     = 6514
}

variable "tls_cert_validity_hours" {
  description = "Server/client certificate validity period in hours. CA validity is 10x this value."
  type        = number
  default     = 8760
}

variable "tls_secret_name" {
  description = "Secrets Manager secret name for TLS certs. Auto-generated if empty."
  type        = string
  default     = ""
}

variable "tls_sidecar_image" {
  description = "Container image for the TLS stunnel sidecar"
  type        = string
  default     = "ghcr.io/aviatrixsystems/siem-connector-tls:latest"
}
```

**Step 2: Pass TLS vars to shared module**

Modify `deployments/aws-ec2-single-instance/main.tf` module call (lines 19-36) — add TLS vars:

```hcl
module "logstash" {
  source = "../modules/aws-logstash"

  vpc_id                      = var.vpc_id
  syslog_port                 = var.syslog_port
  syslog_protocol             = var.syslog_protocol
  instance_size               = var.instance_size
  ssh_key_name                = var.ssh_key_name
  use_existing_security_group = var.use_existing_security_group
  existing_security_group_id  = var.existing_security_group_id
  logstash_config_path        = local.config_path
  logstash_config_name        = local.config_name
  patterns_path               = local.patterns_path
  docker_run_template_path    = local.docker_run_path
  logstash_config_variables   = var.logstash_config_variables
  log_profile                 = var.log_profile
  tags                        = var.tags

  # TLS
  tls_enabled       = var.tls_enabled
  tls_port          = var.tls_port
  tls_secret_arn    = var.tls_enabled ? module.tls[0].secret_arn : ""
  tls_sidecar_image = var.tls_sidecar_image
  aws_region        = var.aws_region
}
```

**Step 3: Create tls.tf**

Create `deployments/aws-ec2-single-instance/tls.tf`:

```hcl
# --- TLS Certificate Generation (conditional) ---
# Remove this file when migrating to controller-managed certs.

module "tls" {
  count  = var.tls_enabled ? 1 : 0
  source = "../modules/tls-certs"

  name_prefix         = "avxlog-${module.logstash.random_suffix}"
  cert_validity_hours = var.tls_cert_validity_hours
  secret_name         = var.tls_secret_name
  tags                = var.tags
}

# --- TLS Outputs ---

output "syslog_endpoint" {
  description = "Syslog destination"
  value       = "${aws_eip.default.public_ip}:${module.logstash.effective_port}"
}

output "tls_ca_certificate_pem" {
  description = "CA cert PEM — upload to Aviatrix as 'Server CA Certificate'"
  value       = var.tls_enabled ? module.tls[0].ca_cert_pem : null
  sensitive   = true
}

output "tls_client_certificate_pem" {
  description = "Client cert PEM — upload to Aviatrix as 'Client Certificate'"
  value       = var.tls_enabled ? module.tls[0].client_cert_pem : null
  sensitive   = true
}

output "tls_client_private_key_pem" {
  description = "Client key PEM — upload to Aviatrix as 'Client Private Key'"
  value       = var.tls_enabled ? module.tls[0].client_key_pem : null
  sensitive   = true
}
```

**Step 4: Validate**

```bash
cd deployments/aws-ec2-single-instance
terraform init -upgrade
terraform validate
```

Expected: "Success! The configuration is valid."

**Step 5: Commit**

```bash
git add deployments/aws-ec2-single-instance/
git commit -m "feat: add TLS support to EC2 single-instance deployment"
```

---

### Task 6: EC2 autoscale TLS wiring

**Files:**
- Modify: `deployments/aws-ec2-autoscale/variables.tf` (add TLS variables)
- Modify: `deployments/aws-ec2-autoscale/main.tf` (pass TLS vars + conditional NLB port)
- Create: `deployments/aws-ec2-autoscale/tls.tf` (call tls-certs module + outputs)

**Step 1: Add TLS variables**

Append to `deployments/aws-ec2-autoscale/variables.tf` (after line 104) — same block as single-instance:

```hcl
# --- TLS Configuration ---

variable "tls_enabled" {
  description = "Enable mTLS syslog ingestion via stunnel sidecar (port 6514 replaces plaintext port 5000)"
  type        = bool
  default     = false
}

variable "tls_port" {
  description = "TLS syslog port (RFC 5425 default: 6514)"
  type        = number
  default     = 6514
}

variable "tls_cert_validity_hours" {
  description = "Server/client certificate validity period in hours. CA validity is 10x this value."
  type        = number
  default     = 8760
}

variable "tls_secret_name" {
  description = "Secrets Manager secret name for TLS certs. Auto-generated if empty."
  type        = string
  default     = ""
}

variable "tls_sidecar_image" {
  description = "Container image for the TLS stunnel sidecar"
  type        = string
  default     = "ghcr.io/aviatrixsystems/siem-connector-tls:latest"
}
```

**Step 2: Pass TLS vars to shared module + update NLB**

Modify `deployments/aws-ec2-autoscale/main.tf`:

Add TLS vars to module call (lines 19-36):

```hcl
module "logstash" {
  source = "../modules/aws-logstash"

  vpc_id                      = var.vpc_id
  syslog_port                 = var.syslog_port
  syslog_protocol             = var.syslog_protocol
  instance_size               = var.instance_size
  ssh_key_name                = var.ssh_key_name
  use_existing_security_group = var.use_existing_security_group
  existing_security_group_id  = var.existing_security_group_id
  logstash_config_path        = local.config_path
  logstash_config_name        = local.config_name
  patterns_path               = local.patterns_path
  docker_run_template_path    = local.docker_run_path
  logstash_config_variables   = var.logstash_config_variables
  log_profile                 = var.log_profile
  tags                        = var.tags

  # TLS
  tls_enabled       = var.tls_enabled
  tls_port          = var.tls_port
  tls_secret_arn    = var.tls_enabled ? module.tls[0].secret_arn : ""
  tls_sidecar_image = var.tls_sidecar_image
  aws_region        = var.aws_region
}
```

Add a local for effective port after the module call:

```hcl
locals {
  effective_port = module.logstash.effective_port
}
```

Update the NLB target group (lines 153-167) and listener (lines 169-179) to use effective_port:

```hcl
resource "aws_lb_target_group" "default" {
  name     = "avxlog-${module.logstash.random_suffix}"
  port     = local.effective_port
  protocol = var.tls_enabled ? "TCP" : upper(var.syslog_protocol)
  vpc_id   = var.vpc_id

  health_check {
    protocol            = "TCP"
    port                = local.effective_port
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
  tags = var.tags
}

resource "aws_lb_listener" "default" {
  load_balancer_arn = aws_lb.default.arn
  port              = local.effective_port
  protocol          = var.tls_enabled ? "TCP" : upper(var.syslog_protocol)

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.default.arn
  }
  tags = var.tags
}
```

**Step 3: Create tls.tf**

Create `deployments/aws-ec2-autoscale/tls.tf`:

```hcl
# --- TLS Certificate Generation (conditional) ---

module "tls" {
  count  = var.tls_enabled ? 1 : 0
  source = "../modules/tls-certs"

  name_prefix         = "avxlog-${module.logstash.random_suffix}"
  cert_validity_hours = var.tls_cert_validity_hours
  secret_name         = var.tls_secret_name
  server_dns_names    = [aws_lb.default.dns_name]
  tags                = var.tags
}

# --- TLS Outputs ---

output "syslog_endpoint" {
  description = "Syslog destination"
  value       = "${aws_lb.default.dns_name}:${local.effective_port}"
}

output "tls_ca_certificate_pem" {
  description = "CA cert PEM — upload to Aviatrix as 'Server CA Certificate'"
  value       = var.tls_enabled ? module.tls[0].ca_cert_pem : null
  sensitive   = true
}

output "tls_client_certificate_pem" {
  description = "Client cert PEM — upload to Aviatrix as 'Client Certificate'"
  value       = var.tls_enabled ? module.tls[0].client_cert_pem : null
  sensitive   = true
}

output "tls_client_private_key_pem" {
  description = "Client key PEM — upload to Aviatrix as 'Client Private Key'"
  value       = var.tls_enabled ? module.tls[0].client_key_pem : null
  sensitive   = true
}
```

**Step 4: Validate**

```bash
cd deployments/aws-ec2-autoscale
terraform init -upgrade
terraform validate
```

Expected: "Success! The configuration is valid."

**Step 5: Commit**

```bash
git add deployments/aws-ec2-autoscale/
git commit -m "feat: add TLS support to EC2 autoscale deployment"
```

---

### Task 7: Optional Aviatrix auto-configuration

**Files:**
- Create: `deployments/aws-ecs-fargate/aviatrix-syslog.tf`
- Create: `deployments/aws-ec2-single-instance/aviatrix-syslog.tf`
- Create: `deployments/aws-ec2-autoscale/aviatrix-syslog.tf`

This task is optional — only needed if the user wants full automation with the Aviatrix Terraform provider.

**Step 1: Create aviatrix-syslog.tf for ECS Fargate**

Create `deployments/aws-ecs-fargate/aviatrix-syslog.tf`:

```hcl
# --- Aviatrix Remote Syslog Configuration (optional) ---
# Remove this file when migrating to controller-managed certs.
# Uncomment and configure the Aviatrix provider to enable.

# variable "aviatrix_controller_ip" {
#   description = "Aviatrix controller IP. Leave empty to configure syslog manually."
#   type        = string
#   default     = ""
# }
#
# variable "aviatrix_syslog_profile_index" {
#   description = "Remote syslog profile index (0-9)"
#   type        = number
#   default     = 0
# }
#
# resource "aviatrix_remote_syslog" "siem" {
#   count = var.tls_enabled && var.aviatrix_controller_ip != "" ? 1 : 0
#
#   index               = var.aviatrix_syslog_profile_index
#   name                = "SIEM Connector"
#   server              = aws_lb.default.dns_name
#   port                = var.tls_port
#   protocol            = "TCP"
#   ca_certificate_file = module.tls[0].ca_cert_pem
#   public_certificate  = module.tls[0].client_cert_pem
#   private_key         = module.tls[0].client_key_pem
# }
```

**Step 2: Copy to EC2 deployments**

Create identical files (adjust endpoint reference) for:
- `deployments/aws-ec2-single-instance/aviatrix-syslog.tf` (use `aws_eip.default.public_ip`)
- `deployments/aws-ec2-autoscale/aviatrix-syslog.tf` (use `aws_lb.default.dns_name`)

**Step 3: Commit**

```bash
git add deployments/*/aviatrix-syslog.tf
git commit -m "feat: add optional Aviatrix remote syslog Terraform resource (commented)"
```

---

### Task 8: GHCR build pipeline update

**Files:**
- Modify: `.github/workflows/release.yml` (if exists — add TLS sidecar image build)

**Step 1: Check if release workflow exists and add TLS sidecar build step**

Look for the existing GHCR build step in the release workflow and add a parallel step for the TLS sidecar image:

```yaml
  build-tls-sidecar:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/build-push-action@v6
        with:
          context: tls-sidecar
          platforms: linux/amd64
          push: true
          tags: |
            ghcr.io/${{ github.repository_owner }}/siem-connector-tls:${{ github.ref_name }}
            ghcr.io/${{ github.repository_owner }}/siem-connector-tls:latest
```

**Step 2: Commit**

```bash
git add .github/workflows/
git commit -m "ci: add TLS sidecar image to release workflow"
```

---

### Task 9: Local integration test

**Prerequisites:** Docker running, tasks 1-6 committed.

**Step 1: Generate test CA + server + client certs**

```bash
mkdir -p /tmp/tls-e2e-test
cd /tmp/tls-e2e-test

# CA
openssl req -x509 -newkey rsa:2048 -keyout ca.key -out ca.crt \
  -days 1 -nodes -subj "/CN=Test CA"

# Server cert
openssl req -newkey rsa:2048 -keyout server.key -out server.csr \
  -nodes -subj "/CN=localhost"
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out server.crt -days 1

# Client cert
openssl req -newkey rsa:2048 -keyout client.key -out client.csr \
  -nodes -subj "/CN=Test Client"
openssl x509 -req -in client.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out client.crt -days 1
```

**Step 2: Start Logstash + stunnel via docker compose**

Create `/tmp/tls-e2e-test/docker-compose.yml`:

```yaml
services:
  stunnel:
    image: ghcr.io/aviatrixsystems/siem-connector-tls:local
    ports:
      - "6514:6514"
    volumes:
      - ./:/etc/stunnel/certs:ro
    depends_on:
      - logstash

  logstash:
    image: docker.elastic.co/logstash/logstash:8.16.2
    volumes:
      - ../../logstash-configs/assembled:/config
      - ../../logstash-configs/patterns:/usr/share/logstash/patterns
    command: logstash -f /config/webhook-test-full.conf
    environment:
      - WEBHOOK_URL=http://host.docker.internal:8080
      - LOG_PROFILE=all
      - XPACK_MONITORING_ENABLED=false
```

Run: `docker compose up -d`

**Step 3: Send a test syslog message over TLS with client cert**

```bash
echo '<13>Mar 10 12:00:00 test-gw AviatrixFQDNRule: FQDN filter matched ...' | \
  openssl s_client -connect localhost:6514 \
    -cert /tmp/tls-e2e-test/client.crt \
    -key /tmp/tls-e2e-test/client.key \
    -CAfile /tmp/tls-e2e-test/ca.crt \
    -quiet
```

Expected: Message passes through stunnel to Logstash. Check Logstash logs for parsed event.

**Step 4: Verify mTLS enforcement — connection WITHOUT client cert should be rejected**

```bash
echo '<13>Mar 10 12:00:00 test-gw unauthorized message' | \
  openssl s_client -connect localhost:6514 \
    -CAfile /tmp/tls-e2e-test/ca.crt \
    -quiet
```

Expected: Connection refused or reset (stunnel `verify = 2` rejects without client cert).

**Step 5: Cleanup**

```bash
cd /tmp/tls-e2e-test && docker compose down
rm -rf /tmp/tls-e2e-test
```

---

## Summary of All Files

| Action | Path |
|--------|------|
| Create | `tls-sidecar/Dockerfile` |
| Create | `tls-sidecar/entrypoint.sh` |
| Create | `tls-sidecar/build.sh` |
| Create | `deployments/modules/tls-certs/main.tf` |
| Create | `deployments/modules/tls-certs/variables.tf` |
| Create | `deployments/modules/tls-certs/outputs.tf` |
| Modify | `deployments/aws-ecs-fargate/variables.tf` |
| Modify | `deployments/aws-ecs-fargate/providers.tf` |
| Create | `deployments/aws-ecs-fargate/tls.tf` |
| Modify | `deployments/aws-ecs-fargate/iam.tf` |
| Modify | `deployments/aws-ecs-fargate/main.tf` |
| Modify | `deployments/aws-ecs-fargate/nlb.tf` |
| Modify | `deployments/aws-ecs-fargate/security-groups.tf` |
| Modify | `deployments/aws-ecs-fargate/outputs.tf` |
| Modify | `deployments/modules/aws-logstash/variables.tf` |
| Modify | `deployments/modules/aws-logstash/main.tf` |
| Modify | `deployments/modules/aws-logstash/logstash_instance_init.tftpl` |
| Modify | `deployments/modules/aws-logstash/outputs.tf` |
| Modify | `deployments/aws-ec2-single-instance/variables.tf` |
| Modify | `deployments/aws-ec2-single-instance/main.tf` |
| Create | `deployments/aws-ec2-single-instance/tls.tf` |
| Modify | `deployments/aws-ec2-autoscale/variables.tf` |
| Modify | `deployments/aws-ec2-autoscale/main.tf` |
| Create | `deployments/aws-ec2-autoscale/tls.tf` |
| Create | `deployments/*/aviatrix-syslog.tf` (3 files, commented) |
| Modify | `.github/workflows/release.yml` |
| **No change** | `logstash-configs/` (inputs, filters, outputs, patterns) |
