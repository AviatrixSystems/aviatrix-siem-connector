output "s3_bucket_id" {
  description = "S3 bucket ID for Logstash config"
  value       = aws_s3_bucket.default.id
}

output "iam_instance_profile_name" {
  description = "IAM instance profile name for EC2 instances"
  value       = aws_iam_instance_profile.default.name
}

output "security_group_id" {
  description = "Security group ID (created or existing)"
  value       = var.use_existing_security_group ? var.existing_security_group_id : aws_security_group.default[0].id
}

output "ami_id" {
  description = "Amazon Linux 2023 AMI ID"
  value       = data.aws_ami.amazon_linux.id
}

output "user_data" {
  description = "Base64-encoded user data for EC2 instances"
  value       = base64encode(local.user_data)
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = lower(random_string.random.id)
}

output "config_etag" {
  description = "ETag of the uploaded config file (for triggering replacements)"
  value       = aws_s3_object.config.etag
}

output "patterns_etag" {
  description = "ETag of the uploaded patterns file (for triggering replacements)"
  value       = aws_s3_object.patterns.etag
}
