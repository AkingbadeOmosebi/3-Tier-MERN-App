
# Backend configuration for Terraform state storage in Azure
# Store my state file in Azure blob storage

terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "sttfstatem9dyyto8"
    container_name       = "tfstate"
    key                  = "01-core-infra.tfstate"
  }
}

