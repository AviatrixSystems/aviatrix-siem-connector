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

variable "tags" {
    description = "Tags to apply to all resources"
    type        = map(string)
    default     = {
        "App" = "avx-log-integration"
    }
}

variable "log_profile" {
    description = "Which log types to forward: all (default), security (suricata, mitm, microseg, fqdn, cmd), or networking (gw_net_stats, gw_sys_stats, tunnel_status)"
    type        = string
    default     = "all"
    validation {
        condition     = contains(["all", "security", "networking"], var.log_profile)
        error_message = "log_profile must be one of: all, security, networking"
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