output "public_ip" {
  description = "Public IP address of the syslog collector"
  value       = aws_eip.syslog_collector_eip.public_ip
}

output "public_dns" {
  description = "Public DNS name of the syslog collector"
  value       = aws_instance.syslog_collector.public_dns
}

output "web_ui_url" {
  description = "URL to access the web UI for log download"
  value       = "http://${aws_eip.syslog_collector_eip.public_ip}"
}

output "syslog_endpoint" {
  description = "Syslog endpoint (UDP and TCP on port 514)"
  value       = "${aws_eip.syslog_collector_eip.public_ip}:514"
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i ~/.ssh/${var.ssh_key_name}.pem ec2-user@${aws_eip.syslog_collector_eip.public_ip}"
}
