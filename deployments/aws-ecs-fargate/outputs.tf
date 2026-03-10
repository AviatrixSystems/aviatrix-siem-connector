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

# --- TLS Outputs ---

output "syslog_endpoint" {
  description = "Syslog destination — configure in Aviatrix controller"
  value       = "${aws_lb.default.dns_name}:${local.effective_port}"
}

output "syslog_protocol" {
  description = "Syslog transport protocol"
  value       = var.tls_enabled ? "TCP+TLS (mTLS)" : "UDP/TCP"
}

output "tls_ca_certificate_pem" {
  description = "CA cert PEM — upload to Aviatrix as 'Server CA Certificate'"
  value       = var.tls_enabled ? module.tls[0].ca_cert_pem : null
  sensitive   = true
}

output "tls_client_certificate_pem" {
  description = "Client cert PEM — upload to Aviatrix as 'Client Certificate'"
  value       = var.tls_enabled ? module.tls[0].client_cert_pem : null
  sensitive   = true
}

output "tls_client_private_key_pem" {
  description = "Client key PEM — upload to Aviatrix as 'Client Private Key'"
  value       = var.tls_enabled ? module.tls[0].client_key_pem : null
  sensitive   = true
}
