variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-2"
}

variable "vpc_id" {
  description = "VPC ID for NLB and ECS tasks"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for NLB and ECS tasks (multi-AZ recommended)"
  type        = list(string)
}

variable "output_type" {
  description = "Logstash output type (splunk-hec, dynatrace, zabbix, etc.)"
  type        = string

  validation {
    condition = contains([
      "splunk-hec",
      "dynatrace",
      "dynatrace-metrics",
      "dynatrace-logs",
      "zabbix",
      "azure-log-ingestion",
    ], var.output_type)
    error_message = "output_type must be one of: splunk-hec, dynatrace, dynatrace-metrics, dynatrace-logs, zabbix, azure-log-ingestion"
  }
}

variable "image_tag" {
  description = "GHCR image tag (e.g., 'latest', 'v1.0.0')"
  type        = string
  default     = "latest"
}

variable "syslog_port" {
  description = "Syslog listener port (TCP and UDP)"
  type        = number
  default     = 5000
}

variable "log_profile" {
  description = "Which log types to forward: all, security, or networking"
  type        = string
  default     = "all"

  validation {
    condition     = contains(["all", "security", "networking"], var.log_profile)
    error_message = "log_profile must be one of: all, security, networking"
  }
}

variable "logstash_config_variables" {
  description = "SIEM-specific environment variables (e.g., SPLUNK_ADDRESS, SPLUNK_HEC_AUTH)"
  type        = map(string)
  default     = {}
}

variable "internal_nlb" {
  description = "Create an internal NLB (true) or internet-facing NLB (false)"
  type        = bool
  default     = false
}

variable "desired_count" {
  description = "Number of Fargate tasks to run"
  type        = number
  default     = 1
}

variable "cpu" {
  description = "Fargate CPU units (256=0.25vCPU, 512=0.5vCPU, 1024=1vCPU)"
  type        = number
  default     = 512
}

variable "memory" {
  description = "Fargate memory in MiB"
  type        = number
  default     = 1024
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default = {
    App = "avx-siem-connector"
  }
}
