# OUTPUTS: Values we need for other modules

output "storage_account_name" {
  description = "Storage account name for Terraform state"
  value       = azurerm_storage_account.tfstate.name
}

output "container_name" {
  description = "Container name for Terraform state files"
  value       = azurerm_storage_container.tfstate.name
}

output "resource_group_name" {
  description = "Resource group containing the storage account"
  value       = azurerm_resource_group.tfstate.name
}

output "access_key" {
  description = "Storage account access key (sensitive)"
  value       = azurerm_storage_account.tfstate.primary_access_key
  sensitive   = true # Won't show in terminal output
}

# Convenient backend configuration template
output "backend_config_example" {
  description = "Example backend configuration for other modules"
  value       = <<-EOT
  
  For my other Terraform modules:
  
  terraform {
    backend "azurerm" {
      resource_group_name  = "${azurerm_resource_group.tfstate.name}"
      storage_account_name = "${azurerm_storage_account.tfstate.name}"
      container_name       = "${azurerm_storage_container.tfstate.name}"
      key                  = "MODULE_NAME.tfstate"  # Change per module
    }
  }
  EOT
}
