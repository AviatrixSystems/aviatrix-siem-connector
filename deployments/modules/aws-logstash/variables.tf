variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "syslog_port" {
  description = "Syslog port"
  type        = number
  default     = 5000
}

variable "syslog_protocol" {
  description = "Syslog protocol (tcp or udp)"
  type        = string
  default     = "tcp"
  validation {
    condition     = contains(["tcp", "udp"], var.syslog_protocol)
    error_message = "syslog_protocol must be \"tcp\" or \"udp\"."
  }
}

variable "allowed_syslog_cidrs" {
  description = "Source CIDRs allowed to reach the syslog (or TLS syslog) port. Defaults to 0.0.0.0/0 for compatibility; restrict to your Aviatrix gateway/controller egress IPs. An empty list creates no syslog ingress rule."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ssh_allowed_cidrs" {
  description = "Source CIDRs allowed to SSH (22/tcp) to the instances. Empty (default) creates no SSH rule."
  type        = list(string)
  default     = []
}

variable "allow_vpc_health_check" {
  description = "Open TCP on the syslog/TLS port from the VPC CIDR for NLB health checks (needed behind an NLB, especially with UDP listeners or restricted allowed_syslog_cidrs)"
  type        = bool
  default     = false
}

variable "ami_id" {
  description = "AMI ID to use. Empty (default) uses the most recent Amazon Linux 2023 AMI; pin it to avoid instance replacement/refresh when a new AMI is published."
  type        = string
  default     = ""
}

variable "output_type" {
  description = "Output type (directory name under logstash-configs/outputs/). Used to require a plugin-capable logstash_image for zabbix and azure-log-ingestion."
  type        = string
  default     = ""
}

variable "instance_size" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "ssh_key_name" {
  description = "SSH key pair name"
  type        = string
  default     = "logstash"
}

variable "use_existing_security_group" {
  description = "Use an existing security group instead of creating one"
  type        = bool
  default     = false
}

variable "existing_security_group_id" {
  description = "Security group ID to use when use_existing_security_group is true"
  type        = string
  default     = ""
}

variable "logstash_config_path" {
  description = "Path to the directory containing the assembled config file"
  type        = string
}

variable "logstash_config_name" {
  description = "Filename of the assembled logstash config (e.g., splunk-hec-full.conf)"
  type        = string
}

variable "patterns_path" {
  description = "Path to the patterns directory"
  type        = string
}

variable "docker_run_template_path" {
  description = "Path to the output-specific docker_run.tftpl"
  type        = string
}

variable "logstash_config_variables" {
  description = "Template variables for the output's docker_run.tftpl (e.g., Splunk HEC token, Dynatrace API token, logstash_image). Stored in Secrets Manager, not in user_data."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "log_profile" {
  description = "Which log types to forward: all (default), security, or networking"
  type        = string
  default     = "all"
  validation {
    condition     = contains(["all", "security", "networking"], var.log_profile)
    error_message = "log_profile must be one of: all, security, networking"
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    "App" = "avx-log-integration"
  }
}

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
  description = "ARN of the Secrets Manager secret containing TLS certs (pass the tls-certs module's secret_version_arn where possible so instances wait for the cert bundle)"
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
