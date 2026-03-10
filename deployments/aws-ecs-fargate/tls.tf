# --- TLS Certificate Generation (conditional) ---
# Remove this file when migrating to controller-managed certs.

module "tls" {
  count  = var.tls_enabled ? 1 : 0
  source = "../modules/tls-certs"

  name_prefix         = local.name_prefix
  cert_validity_hours = var.tls_cert_validity_hours
  secret_name         = var.tls_secret_name
  server_dns_names = concat(
    [aws_lb.default.dns_name],
    var.tls_server_dns_names,
  )
  tags = var.tags
}
