# --- Aviatrix Remote Syslog Configuration (optional) ---
# Uncomment this file and configure the Aviatrix provider to auto-configure
# remote syslog on the Aviatrix controller.
# Remove this file when migrating to controller-managed certs.

# variable "aviatrix_controller_ip" {
#   description = "Aviatrix controller IP. Leave empty to configure syslog manually."
#   type        = string
#   default     = ""
# }
#
# variable "aviatrix_syslog_profile_index" {
#   description = "Remote syslog profile index (0-9)"
#   type        = number
#   default     = 0
# }
#
# resource "aviatrix_remote_syslog" "siem" {
#   count = var.tls_enabled && var.aviatrix_controller_ip != "" ? 1 : 0
#
#   index               = var.aviatrix_syslog_profile_index
#   name                = "SIEM Connector"
#   server              = aws_lb.default.dns_name
#   port                = var.tls_port
#   protocol            = "TCP"
#   ca_certificate_file = module.tls[0].ca_cert_pem
#   public_certificate  = module.tls[0].client_cert_pem
#   private_key         = module.tls[0].client_key_pem
# }
