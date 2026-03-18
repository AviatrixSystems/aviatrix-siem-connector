output "secret_arn" {
  description = "ARN of the Secrets Manager secret containing server certs"
  value       = aws_secretsmanager_secret.tls.arn
}

output "ca_cert_pem" {
  description = "CA certificate PEM -- upload to Aviatrix as 'Server CA Certificate'"
  value       = tls_self_signed_cert.ca.cert_pem
  sensitive   = true
}

output "client_cert_pem" {
  description = "Client certificate PEM -- upload to Aviatrix as 'Client Certificate'"
  value       = tls_locally_signed_cert.client.cert_pem
  sensitive   = true
}

output "client_key_pem" {
  description = "Client private key PEM -- upload to Aviatrix as 'Client Private Key'"
  value       = tls_private_key.client.private_key_pem
  sensitive   = true
}
