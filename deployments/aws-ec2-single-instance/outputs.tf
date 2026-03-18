output "avx_syslog_destination" {
  value = aws_eip.default.public_ip
}

output "avx_syslog_port" {
  value = module.logstash.effective_port
}

output "avx_syslog_proto" {
  value = var.tls_enabled ? "tcp+tls" : var.syslog_protocol
}
