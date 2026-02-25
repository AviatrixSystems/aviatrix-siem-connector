output "ecr_repository_url" {
  description = "ECR repository URL — use with build-and-push.sh"
  value       = aws_ecr_repository.default.repository_url
}

output "nlb_dns_name" {
  description = "NLB DNS name — configure as syslog destination in Aviatrix"
  value       = aws_lb.default.dns_name
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.default.name
}

output "ecs_service_name" {
  value = var.container_image != "" ? aws_ecs_service.default[0].name : ""
}

output "build_command" {
  description = "Ready-to-paste command to build and push the container image"
  value       = "./container-build/build-and-push.sh --output-type ${var.output_type} --ecr-repo ${aws_ecr_repository.default.repository_url} --region ${var.aws_region}"
}
