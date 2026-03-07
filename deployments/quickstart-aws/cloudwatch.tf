resource "aws_cloudwatch_log_group" "logstash" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = 30
  tags              = var.tags
}
