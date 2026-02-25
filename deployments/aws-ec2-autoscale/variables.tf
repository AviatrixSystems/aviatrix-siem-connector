variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-2"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "instance_subnet_ids" {
  description = "Subnet IDs for EC2 instances (use different AZs for HA)"
  type        = list(string)
}

variable "lb_subnet_ids" {
  description = "Subnet IDs for the Network Load Balancer (use different AZs)"
  type        = list(string)
}

variable "assign_instance_public_ip" {
  description = "Assign public IP to instances"
  type        = bool
  default     = false
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

variable "autoscale_min_size" {
  description = "Minimum number of instances in the autoscaling group"
  type        = number
  default     = 2
}

variable "autoscale_max_size" {
  description = "Maximum number of instances in the autoscaling group"
  type        = number
  default     = 6
}

variable "autoscale_step_size" {
  description = "Number of instances to add/remove when scaling"
  type        = number
  default     = 2
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
