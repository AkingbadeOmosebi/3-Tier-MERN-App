terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "sttfstatem9dyyto8"
    container_name       = "tfstate"
    key                  = "cosmos-db.tfstate"
  }
}