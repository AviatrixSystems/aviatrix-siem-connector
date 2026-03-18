variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-2"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for both NLB and ECS tasks (use multiple AZs for HA)"
  type        = list(string)
}

variable "output_type" {
  description = "Output type (must match a directory in logstash-configs/outputs/)"
  type        = string
  default     = "splunk-hec"
}

variable "container_image" {
  description = "Container image URI (e.g. 123456789.dkr.ecr.us-east-2.amazonaws.com/avx-logstash:latest). Leave empty to skip ECS service creation."
  type        = string
  default     = ""
}

variable "syslog_port" {
  description = "Syslog port"
  type        = number
  default     = 5000
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

variable "logstash_config_variables" {
  description = "Environment variables for the Logstash container (e.g., Splunk HEC token, Dynatrace API token)"
  type        = map(string)
  default     = {}
}

variable "desired_count" {
  description = "Number of Fargate tasks to run"
  type        = number
  default     = 1
}

variable "cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU, 512 = 0.5 vCPU, 1024 = 1 vCPU)"
  type        = number
  default     = 512
}

variable "memory" {
  description = "Fargate task memory in MiB"
  type        = number
  default     = 1024
}

variable "assign_public_ip" {
  description = "Assign public IP to tasks (required for ECR pull from public subnets without NAT gateway)"
  type        = bool
  default     = true
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights on the ECS cluster"
  type        = bool
  default     = true
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
