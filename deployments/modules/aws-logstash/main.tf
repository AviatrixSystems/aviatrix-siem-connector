resource "random_string" "random" {
  length  = 10
  special = false
}

# S3 bucket for Logstash config and patterns
resource "aws_s3_bucket" "default" {
  bucket = "avxlog-${lower(random_string.random.id)}"
  tags   = var.tags
}

resource "aws_s3_bucket_public_access_block" "default" {
  bucket                  = aws_s3_bucket.default.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "config" {
  bucket = aws_s3_bucket.default.id
  key    = var.logstash_config_name
  source = "${var.logstash_config_path}/${var.logstash_config_name}"
  etag   = md5(file("${var.logstash_config_path}/${var.logstash_config_name}"))
  tags   = var.tags
}

resource "aws_s3_object" "patterns" {
  bucket = aws_s3_bucket.default.id
  key    = "avx.conf"
  source = "${var.patterns_path}/avx.conf"
  etag   = md5(file("${var.patterns_path}/avx.conf"))
  tags   = var.tags
}

# IAM role for EC2 instances to read S3
resource "aws_iam_policy" "s3_read_policy" {
  name        = "avxlog-s3-${lower(random_string.random.id)}"
  description = "Policy to allow EC2 instances to read a specific S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = ["s3:GetObject"],
        Effect   = "Allow",
        Resource = ["${aws_s3_bucket.default.arn}/*"]
      },
    ],
  })
  tags = var.tags
}

resource "aws_iam_role" "ec2_s3_access_role" {
  name = "avxlog-role-${lower(random_string.random.id)}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
      },
    ],
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "s3_read_attach" {
  role       = aws_iam_role.ec2_s3_access_role.name
  policy_arn = aws_iam_policy.s3_read_policy.arn
}

# Instances read the rendered Logstash container command (which carries the
# SIEM credentials) and, with TLS, the cert bundle from Secrets Manager.
resource "aws_iam_policy" "secrets_read_policy" {
  name        = "avxlog-secrets-${lower(random_string.random.id)}"
  description = "Policy to allow EC2 instances to read the Logstash runtime (and TLS) secrets"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action   = "secretsmanager:GetSecretValue",
      Effect   = "Allow",
      Resource = compact([aws_secretsmanager_secret.runtime.arn, var.tls_enabled ? var.tls_secret_arn : ""])
    }],
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "secrets_read_attach" {
  role       = aws_iam_role.ec2_s3_access_role.name
  policy_arn = aws_iam_policy.secrets_read_policy.arn
}

# SSM Session Manager access (SSH is closed by default)
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_s3_access_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "default" {
  name = "avxlog-profile-${lower(random_string.random.id)}"
  role = aws_iam_role.ec2_s3_access_role.name
  tags = var.tags
}

# Security group (conditionally created)
data "aws_vpc" "selected" {
  count = var.allow_vpc_health_check && !var.use_existing_security_group ? 1 : 0
  id    = var.vpc_id
}

resource "aws_security_group" "default" {
  count  = var.use_existing_security_group ? 0 : 1
  name   = "avxlog-${lower(random_string.random.id)}"
  vpc_id = var.vpc_id

  # Syslog (or TLS syslog) from the allowed source ranges
  dynamic "ingress" {
    for_each = length(var.allowed_syslog_cidrs) > 0 ? [1] : []
    content {
      from_port   = var.tls_enabled ? var.tls_port : var.syslog_port
      to_port     = var.tls_enabled ? var.tls_port : var.syslog_port
      protocol    = var.tls_enabled ? "tcp" : var.syslog_protocol
      cidr_blocks = var.allowed_syslog_cidrs
    }
  }

  # NLB TCP health checks come from the load balancer's private IPs inside the
  # VPC. They are TCP even when the listener is UDP, so open TCP from the VPC
  # CIDR (Logstash listens on both TCP and UDP).
  dynamic "ingress" {
    # Skipped when the syslog rule above already allows TCP from the VPC CIDR
    # (a duplicate rule would be rejected by EC2).
    for_each = !var.allow_vpc_health_check ? [] : (
      (var.tls_enabled || var.syslog_protocol == "tcp") && contains(var.allowed_syslog_cidrs, data.aws_vpc.selected[0].cidr_block) ? [] : [1]
    )
    content {
      description = "NLB TCP health check"
      from_port   = var.tls_enabled ? var.tls_port : var.syslog_port
      to_port     = var.tls_enabled ? var.tls_port : var.syslog_port
      protocol    = "tcp"
      cidr_blocks = [data.aws_vpc.selected[0].cidr_block]
    }
  }

  # SSH is off unless ssh_allowed_cidrs is set (use SSM Session Manager or an
  # explicit admin CIDR instead of 0.0.0.0/0)
  dynamic "ingress" {
    for_each = length(var.ssh_allowed_cidrs) > 0 ? [1] : []
    content {
      description = "SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.ssh_allowed_cidrs
    }
  }

  egress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = var.tags
}

# Amazon Linux 2023 AMI (standard image family only; "al2023-ami-minimal-*" is
# excluded). Set var.ami_id to pin an image and avoid replacements whenever
# Amazon publishes a new AMI.
data "aws_ami" "amazon_linux" {
  count       = var.ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# --- Per-output runtime contract ---
# The output's docker_run.tftpl is the single source of image + env for the
# Logstash container in BOTH plaintext and TLS mode. Defaults below are merged
# under the user's logstash_config_variables so optional keys never break
# templatefile(); templates ignore keys they do not use.
locals {
  # Outputs whose plugin is not bundled with the stock Logstash image
  plugin_outputs = ["zabbix", "azure-log-ingestion"]

  template_defaults = {
    logstash_image     = "docker.elastic.co/logstash/logstash:8.16.2"
    splunk_port        = "8088"
    dt_environment_id  = ""
    dt_region          = "apps"
    dt_metrics_url     = ""
    dt_logs_url        = ""
    dt_metric_source   = "aviatrix"
    dt_log_source      = "aviatrix"
    dt_logs_token      = lookup(var.logstash_config_variables, "dt_api_token", "")
    zabbix_port        = "10051"
    zabbix_host_prefix = ""
  }

  logstash_run_command = templatefile(var.docker_run_template_path, merge(
    local.template_defaults,
    var.logstash_config_variables,
    {
      log_profile = var.log_profile
      syslog_port = var.syslog_port
    },
  ))
}

# The rendered `docker run` command carries SIEM credentials, so it is stored
# in Secrets Manager and fetched at boot instead of being embedded in
# user_data (readable via ec2:DescribeInstanceAttribute / IMDS).
resource "aws_secretsmanager_secret" "runtime" {
  name                    = "avxlog-${lower(random_string.random.id)}-runtime"
  description             = "Rendered Logstash container command for the Aviatrix SIEM connector"
  recovery_window_in_days = 0
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "runtime" {
  secret_id     = aws_secretsmanager_secret.runtime.id
  secret_string = local.logstash_run_command

  lifecycle {
    precondition {
      condition     = !contains(local.plugin_outputs, var.output_type) || contains(keys(var.logstash_config_variables), "logstash_image")
      error_message = "output_type \"${var.output_type}\" needs a Logstash image that includes its output plugin (the stock docker.elastic.co image does not). Set logstash_config_variables.logstash_image to such an image, e.g. one built from logstash-configs/outputs/zabbix/Containerfile or deployments/azure-aci/logstash-container-build."
    }
    precondition {
      condition = var.syslog_port == 5000 || (
        length(regexall("SYSLOG_PORT", file(var.docker_run_template_path))) > 0 &&
        length(regexall("SYSLOG_PORT", file("${var.logstash_config_path}/${var.logstash_config_name}"))) > 0
      )
      error_message = "syslog_port is ${var.syslog_port}, but the output's docker_run.tftpl or the assembled config (${var.logstash_config_name}) does not honor SYSLOG_PORT, so Logstash would still listen on 5000. Re-run logstash-configs/scripts/assemble-config.sh or use syslog_port = 5000."
    }
  }
}

# User data: bootstrap script that fetches config + runtime command
locals {
  user_data = templatefile("${path.module}/logstash_instance_init.tftpl", {
    aws_s3_bucket_id     = aws_s3_bucket.default.id
    logstash_config_name = aws_s3_object.config.key
    # Etags/version make user_data (and so the launch template / instance)
    # change whenever the config, patterns or runtime command change.
    config_etag        = aws_s3_object.config.etag
    patterns_etag      = aws_s3_object.patterns.etag
    runtime_secret_arn = aws_secretsmanager_secret_version.runtime.arn
    runtime_version_id = aws_secretsmanager_secret_version.runtime.version_id
    aws_region         = var.aws_region
    syslog_port        = var.syslog_port
    tls_enabled        = var.tls_enabled
    tls_secret_arn     = var.tls_secret_arn
    tls_port           = var.tls_port
    tls_sidecar_image  = var.tls_sidecar_image
  })
}

# Policy used to be count-based (TLS only); it now always exists for the
# runtime secret.
moved {
  from = aws_iam_policy.secrets_read_policy[0]
  to   = aws_iam_policy.secrets_read_policy
}

moved {
  from = aws_iam_role_policy_attachment.secrets_read_attach[0]
  to   = aws_iam_role_policy_attachment.secrets_read_attach
}
