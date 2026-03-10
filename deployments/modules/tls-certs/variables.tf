variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "cert_validity_hours" {
  description = "Validity period for server and client certs (CA is 10x)"
  type        = number
  default     = 8760 # 1 year
}

variable "server_common_name" {
  description = "Common name for the server certificate"
  type        = string
  default     = "siem-connector"
}

variable "server_dns_names" {
  description = "DNS SANs for the server certificate (e.g., NLB DNS name)"
  type        = list(string)
  default     = []
}

variable "server_ip_addresses" {
  description = "IP SANs for the server certificate"
  type        = list(string)
  default     = []
}

variable "organization" {
  description = "Organization name for certificate subjects"
  type        = string
  default     = "Aviatrix SIEM Connector"
}

variable "secret_name" {
  description = "Secrets Manager secret name. Auto-generated if empty."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
