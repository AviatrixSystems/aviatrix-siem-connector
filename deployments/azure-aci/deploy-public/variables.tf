variable "resource_group_name" {
  description = "Name of the resource group for the container instance"
  type        = string
  default     = "logstash-aci-rg"
}

variable "location" {
  description = "Azure region for deployment"
  type        = string
  default     = "France Central"
}

variable "container_name" {
  description = "Name of the container"
  type        = string
  default     = "logstash"
}

variable "container_image" {
  description = "Logstash image WITH the microsoft-sentinel-log-analytics-logstash-output-plugin installed (see ../logstash-container-build/). Required: the stock Elastic image cannot load the Azure pipeline."
  type        = string

  validation {
    condition     = !startswith(var.container_image, "docker.elastic.co/logstash/")
    error_message = "container_image must be a custom image with the Microsoft Sentinel output plugin installed; the stock docker.elastic.co/logstash image cannot load the Azure pipeline. Build one with deployments/azure-aci/logstash-container-build/."
  }
}

variable "container_registry_server" {
  description = "Optional private registry login server for container_image (e.g. myacr.azurecr.io). When set, ACI pulls with the credentials below instead of requiring anonymous pull on the registry."
  type        = string
  default     = null
}

variable "container_registry_username" {
  description = "Registry username (ACR admin user, ACR token name, or service principal client ID). Used only when container_registry_server is set."
  type        = string
  default     = null
}

variable "container_registry_password" {
  description = "Registry password. Used only when container_registry_server is set."
  type        = string
  default     = null
  sensitive   = true
}

variable "cpu_cores" {
  description = "Number of CPU cores for the container"
  type        = number
  default     = 1
}

variable "memory_gb" {
  description = "Memory in GB for the container"
  type        = number
  default     = 1.5
}

variable "container_port" {
  description = "Port to expose on the container"
  type        = number
  default     = 5000
}

variable "container_protocol" {
  description = "Protocol for the container port"
  type        = string
  default     = "TCP"
  validation {
    condition     = contains(["TCP", "UDP"], var.container_protocol)
    error_message = "Protocol must be either TCP or UDP."
  }
}

variable "storage_account_name" {
  description = "Name of the storage account for Logstash configuration files"
  type        = string
  default     = "logstashstorage"

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account name must be between 3 and 24 characters long and contain only lowercase letters and numbers."
  }
}

variable "file_share_quota_gb" {
  description = "Quota for the file share in GB"
  type        = number
  default     = 5

  validation {
    condition     = var.file_share_quota_gb >= 1 && var.file_share_quota_gb <= 102400
    error_message = "File share quota must be between 1 and 102400 GB."
  }
}

variable "log_analytics_workspace_name" {
  description = "Name of the existing Log Analytics workspace"
  type        = string
  default     = "we-log-ws"
}

variable "log_analytics_resource_group_name" {
  description = "Resource group name of the existing Log Analytics workspace"
  type        = string
  default     = "we-loga-rg"
}

variable "environment_variables" {
  description = "Environment variables for the container (Logstash JVM/runtime settings). Stream names and DCR IDs are injected automatically by the module."
  type        = map(string)
  default = {
    "LS_JAVA_OPTS"             = "-Xmx1g -Xms1g"
    "LOG_LEVEL"                = "info"
    "XPACK_MONITORING_ENABLED" = "false"
    "PIPELINE_WORKERS"         = "1"
    "CONFIG_RELOAD_AUTOMATIC"  = "true"
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "production"
    Project     = "siem-connector"
    Service     = "logstash"
  }
}

variable "use_existing_spn" {
  description = "Whether to use an existing service principal (true) or create a new one (false) for the plugin to send logs to Log Analytics via DCR rules"
  type        = bool
  default     = true
}

variable "client_app_id" {
  description = "Client (application) ID of the existing service principal. Required when use_existing_spn = true."
  type        = string
  default     = null

  validation {
    condition     = var.client_app_id == null || can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.client_app_id))
    error_message = "client_app_id must be a GUID."
  }
}

variable "client_app_secret" {
  description = "Client secret of the existing service principal. Required when use_existing_spn = true."
  type        = string
  default     = null
  sensitive   = true
}

variable "tenant_id" {
  description = "Entra ID tenant ID of the existing service principal. Required when use_existing_spn = true."
  type        = string
  default     = null

  validation {
    condition     = var.tenant_id == null || can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.tenant_id))
    error_message = "tenant_id must be a GUID."
  }
}

variable "spn_secret_rotation_days" {
  description = "When use_existing_spn = false, rotate the generated SPN secret after this many days (takes effect on the next terraform apply after that date; the old secret stays valid 30 more days)."
  type        = number
  default     = 180
}

variable "azure_cloud" {
  description = "Azure cloud environment: 'AzureCloud' (default) or 'AzureUSGovernment'. Sets both the Sentinel output plugin cloud and the azurerm/azuread/azapi provider environment. Use ../deploy-china for AzureChinaCloud."
  type        = string
  default     = "AzureCloud"

  validation {
    condition     = contains(["AzureCloud", "AzureUSGovernment"], var.azure_cloud)
    error_message = "deploy-public supports azure_cloud = \"AzureCloud\" or \"AzureUSGovernment\". Use deploy-china for AzureChinaCloud."
  }
}

variable "log_analytics_subscription_id" {
  description = "Subscription ID for the Log Analytics workspace"
  type        = string
  default     = "dummy"
}
