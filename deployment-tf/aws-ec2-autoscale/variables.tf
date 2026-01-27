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
  description = "Path to assembled logstash config directory"
  default     = "../../logstash-configs/assembled"
}

variable "logstash_config_name" {
  description = "Name of assembled logstash config file"
  default     = "splunk-hec-full.conf"
}

variable "logstash_patterns_path" {
  description = "Path to logstash patterns directory"
  default     = "../../logstash-configs/patterns"
}

variable "docker_run_template_path" {
  description = "Path to docker run template file"
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

variable "logstash_config_variables" {
    #map variable
    type = map(string)
    default = {
      "name" = "value"
    }
}