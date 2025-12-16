# Backend Configuration for AKS Cluster State

terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "sttfstatem9dyyto8"
    container_name       = "tfstate"
    key                  = "aks-cluster.tfstate"  # Unique key for the AKS cluster state file
  }
}