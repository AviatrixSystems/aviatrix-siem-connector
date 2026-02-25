output "avx_syslog_destination" {
  value = aws_eip.default.public_ip
}

output "avx_syslog_port" {
  value = var.syslog_port
}

output "avx_syslog_proto" {
  value = var.syslog_protocol
}
