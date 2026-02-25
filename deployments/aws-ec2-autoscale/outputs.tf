output "avx_syslog_destination" {
  value = aws_lb.default.dns_name
}

output "avx_syslog_port" {
  value = var.syslog_port
}

output "avx_syslog_proto" {
  value = var.syslog_protocol
}
