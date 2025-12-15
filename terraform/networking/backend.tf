
# Backend configuration for Networking module

terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "sttfstatem9dyyto8"
    container_name       = "tfstate"
    key                  = "networking.tfstate"  # each module gets its own state file with a unique key name
  }
}