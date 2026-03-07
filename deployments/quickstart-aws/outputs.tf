output "syslog_endpoint" {
  description = "Syslog endpoint — configure this in your Aviatrix Controller"
  value       = "${aws_lb.default.dns_name}:${var.syslog_port}"
}

output "nlb_dns_name" {
  description = "NLB DNS name"
  value       = aws_lb.default.dns_name
}

output "ecs_cluster_name" {
  description = "ECS cluster name (for troubleshooting)"
  value       = aws_ecs_cluster.default.name
}

output "ecs_service_name" {
  description = "ECS service name (for troubleshooting)"
  value       = aws_ecs_service.default.name
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group (for viewing Logstash logs)"
  value       = aws_cloudwatch_log_group.logstash.name
}
