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

variable "instance_subnet_ids" {
    description = "Subnet IDs"
    type        = list(string)
}

variable "lb_subnet_ids" {
    description = "Subnet IDs"
    type        = list(string)
}

variable "assign_instance_public_ip" {
  description = "Assign public IP to instances"
  default     = false
  
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

variable "logstash_config_path" {
  description = "Path to the assembled output config directory (must contain both .conf file and docker_run.tftpl)"
  default     = "../../logstash-configs/assembled"
}

variable "logstash_config_name" {
  description = "Name of the assembled logstash config file (e.g., splunk-hec-full.conf, azure-log-ingestion-full.conf)"
  default     = "splunk-hec-full.conf"
}

variable "logstash_patterns_path" {
  description = "Base path to logstash configs directory (should contain patterns/ subdirectory)"
  default     = "../../logstash-configs/patterns"
}

variable "docker_run_template_path" {
  description = "Path to docker run template file (docker_run.tftpl for the output type)"
  default     = "../../logstash-configs/outputs/splunk-hec/docker_run.tftpl"
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