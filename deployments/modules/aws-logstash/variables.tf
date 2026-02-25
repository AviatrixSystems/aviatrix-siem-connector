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
  description = "Syslog protocol"
  type        = string
  default     = "tcp"
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
  description = "Environment variables passed to the Docker container (e.g., Splunk HEC token, Dynatrace API token)"
  type        = map(string)
  default     = {}
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
