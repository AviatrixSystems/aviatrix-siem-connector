# --- TLS Certificate Generation (conditional) ---
# Remove this file when migrating to controller-managed certs.

module "tls" {
  count  = var.tls_enabled ? 1 : 0
  source = "../modules/tls-certs"

  name_prefix         = "avxlog-${module.logstash.random_suffix}"
  cert_validity_hours = var.tls_cert_validity_hours
  secret_name         = var.tls_secret_name
  tags                = var.tags
}

# --- TLS Outputs ---

output "syslog_endpoint" {
  description = "Syslog destination"
  value       = "${aws_eip.default.public_ip}:${module.logstash.effective_port}"
}

output "tls_ca_certificate_pem" {
  description = "CA cert PEM -- upload to Aviatrix as 'Server CA Certificate'"
  value       = var.tls_enabled ? module.tls[0].ca_cert_pem : null
  sensitive   = true
}

output "tls_client_certificate_pem" {
  description = "Client cert PEM -- upload to Aviatrix as 'Client Certificate'"
  value       = var.tls_enabled ? module.tls[0].client_cert_pem : null
  sensitive   = true
}

output "tls_client_private_key_pem" {
  description = "Client key PEM -- upload to Aviatrix as 'Client Private Key'"
  value       = var.tls_enabled ? module.tls[0].client_key_pem : null
  sensitive   = true
}
