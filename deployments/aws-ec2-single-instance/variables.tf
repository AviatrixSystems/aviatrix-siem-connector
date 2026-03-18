variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-2"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the EC2 instance"
  type        = string
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

variable "syslog_port" {
  description = "Syslog port"
  type        = number
  default     = 5000
}

variable "syslog_protocol" {
  description = "Syslog protocol"
  type        = string
  default     = "tcp"
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
