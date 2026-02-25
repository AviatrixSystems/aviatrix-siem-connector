provider "aws" {
  region = var.aws_region
}

variable "output_type" {
  description = "Output type (must match a directory in logstash-configs/outputs/)"
  type        = string
  default     = "splunk-hec"
}

locals {
  logstash_base   = "${path.module}/../../logstash-configs"
  config_path     = "${local.logstash_base}/assembled"
  config_name     = "${var.output_type}-full.conf"
  docker_run_path = "${local.logstash_base}/outputs/${var.output_type}/docker_run.tftpl"
  patterns_path   = "${local.logstash_base}/patterns"
}

module "logstash" {
  source = "../modules/aws-logstash"

  vpc_id                      = var.vpc_id
  syslog_port                 = var.syslog_port
  syslog_protocol             = var.syslog_protocol
  instance_size               = var.instance_size
  ssh_key_name                = var.ssh_key_name
  use_existing_security_group = var.use_existing_security_group
  existing_security_group_id  = var.existing_security_group_id
  logstash_config_path        = local.config_path
  logstash_config_name        = local.config_name
  patterns_path               = local.patterns_path
  docker_run_template_path    = local.docker_run_path
  logstash_config_variables   = var.logstash_config_variables
  log_profile                 = var.log_profile
  tags                        = var.tags
}

resource "terraform_data" "config_etag" {
  input = module.logstash.config_etag
}

resource "terraform_data" "patterns_etag" {
  input = module.logstash.patterns_etag
}

resource "aws_instance" "default" {
  ami                         = module.logstash.ami_id
  instance_type               = var.instance_size
  key_name                    = var.ssh_key_name
  iam_instance_profile        = module.logstash.iam_instance_profile_name
  user_data_replace_on_change = true

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.default.id
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
  }

  user_data = module.logstash.user_data

  tags = merge({
    Name = "avxlog-${module.logstash.random_suffix}"
  }, var.tags)

  lifecycle {
    replace_triggered_by = [terraform_data.config_etag, terraform_data.patterns_etag]
  }
}

resource "aws_network_interface" "default" {
  subnet_id       = var.subnet_id
  tags            = var.tags
  security_groups = [module.logstash.security_group_id]
}

resource "aws_eip" "default" {
  instance = aws_instance.default.id
}

resource "aws_eip_association" "eip_assoc" {
  allocation_id        = aws_eip.default.id
  network_interface_id = aws_network_interface.default.id
}
