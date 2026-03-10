# -----------------------------------------------------------------------------
# TLS Certificate Module
#
# Generates a full PKI for mTLS between Aviatrix gateways and the SIEM
# connector:
#   - Self-signed CA (long-lived, 10x cert validity)
#   - Server certificate signed by CA (for stunnel sidecar)
#   - Client certificate signed by CA (for Aviatrix controller)
#   - Secrets Manager secret storing server cert + key + CA cert
# -----------------------------------------------------------------------------

terraform {
  required_providers {
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# =============================================================================
# CA — long-lived root (10x cert validity)
# =============================================================================

resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem = tls_private_key.ca.private_key_pem

  subject {
    common_name  = "${var.name_prefix} CA"
    organization = var.organization
  }

  validity_period_hours = var.cert_validity_hours * 10
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

# =============================================================================
# Server certificate — signed by CA
# =============================================================================

resource "tls_private_key" "server" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "server" {
  private_key_pem = tls_private_key.server.private_key_pem

  subject {
    common_name  = var.server_common_name
    organization = var.organization
  }

  dns_names    = var.server_dns_names
  ip_addresses = var.server_ip_addresses
}

resource "tls_locally_signed_cert" "server" {
  cert_request_pem   = tls_cert_request.server.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = var.cert_validity_hours

  allowed_uses = [
    "server_auth",
    "digital_signature",
    "key_encipherment",
  ]
}

# =============================================================================
# Client certificate — signed by CA
# =============================================================================

resource "tls_private_key" "client" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "client" {
  private_key_pem = tls_private_key.client.private_key_pem

  subject {
    common_name  = "${var.name_prefix} Client"
    organization = var.organization
  }
}

resource "tls_locally_signed_cert" "client" {
  cert_request_pem   = tls_cert_request.client.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = var.cert_validity_hours

  allowed_uses = [
    "client_auth",
    "digital_signature",
    "key_encipherment",
  ]
}

# =============================================================================
# Secrets Manager — server cert bundle (consumed by stunnel sidecar)
# =============================================================================

resource "aws_secretsmanager_secret" "tls" {
  name                    = var.secret_name != "" ? var.secret_name : "${var.name_prefix}-tls-certs"
  recovery_window_in_days = 0
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "tls" {
  secret_id = aws_secretsmanager_secret.tls.id

  secret_string = jsonencode({
    server_cert = tls_locally_signed_cert.server.cert_pem
    server_key  = tls_private_key.server.private_key_pem
    ca_cert     = tls_self_signed_cert.ca.cert_pem
  })
}
