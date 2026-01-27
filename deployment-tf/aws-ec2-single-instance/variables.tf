variable "aws_region" {
  description = "AWS Region"
  default     = "us-east-2"
}

variable "logstash_instance_size" {
  description = "Instance size for Logstash instances"
  default     = "t3.small"
}

variable "ssh_key_name" {
  description = "SSH key name"
  default     = "logstash"
}

variable "vpc_id" {
  description = "VPC ID"
}

variable "subnet_id" {
    description = "Subnet ID"
}

variable "use_existing_copilot_security_group" {
  description = "Use existing security group for Copilot"
  default     = false
}

variable "copilot_security_group_id" {
  description = "Security group ID for Copilot"
  default=""
}

variable "syslog_port" {
  description = "Syslog port"
  default     = 5000
}

variable "syslog_protocol" {
  description = "Syslog protocol"
  default     = "tcp"
}

variable "logstash_base_config_path" {
  description = "Base path to logstash configs directory (should contain patterns/ subdirectory)"
  default     = "../../logstash-configs"
}

variable "logstash_output_config_path" {
  description = "Path to the assembled output config directory (must contain both .conf file and docker_run.tftpl)"
  default     = "../../logstash-configs/assembled"
}

variable "logstash_output_config_name" {
  description = "Name of the assembled logstash config file (e.g., splunk-hec-full.conf, azure-log-ingestion-full.conf)"
  default     = "splunk-hec-full.conf"
}

variable "autoscale_min_size" {
    description = "Minimum number of instances in autoscale group"
    default     = 2
}

variable "autoscale_max_size" {
    description = "Maximum number of instances in autoscale group"
    default     = 6
}

variable "autoscale_step_size" {
    description = "Number of instances to add/remove when scaling"
    default     = 2
}

variable "tags" {
    description = "Tags to apply to all resources"
    type        = map(string)
    default     = {
        "App" = "avx-log-integration"
    }
}

variable "logstash_config_variables" {
    description = "Environment variables for Logstash container (e.g., Splunk HEC token, address, port)"
    type = map(string)
    default = {
      "splunk_hec_auth" = "YOUR_SPLUNK_HEC_TOKEN_HERE",
      "splunk_port" = "8088",
      "splunk_address" = "https://YOUR_SPLUNK_IP_HERE"
    }
}