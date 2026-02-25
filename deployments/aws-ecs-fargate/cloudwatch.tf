# --- CloudWatch Log Group for Logstash container logs ---

resource "aws_cloudwatch_log_group" "default" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = 30

  tags = var.tags
}
