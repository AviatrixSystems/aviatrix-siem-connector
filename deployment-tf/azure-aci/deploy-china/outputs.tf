output "container_group_fqdn" {
  description = "FQDN of the container group"
  value       = module.deployment.container_group_fqdn
}

output "resource_group_name" {
  description = "Name of the resource group"
  value       = module.deployment.resource_group_name
}

output "storage_account_name" {
  description = "Name of the storage account for Logstash configuration"
  value       = module.deployment.storage_account_name
}

output "container_group_name" {
  description = "Name of the Logstash container group"
  value       = module.deployment.container_group_name
}

output "attach_container_command" {
  description = "Copy / paste this command to attach to container"
  value       = "az container attach --resource-group ${module.deployment.resource_group_name} --name ${module.deployment.container_group_name}"
}
