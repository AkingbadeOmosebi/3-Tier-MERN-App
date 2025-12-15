
# BOOTSTRAP: Terraform State Backend
# Purpose: Creates Azure Storage Account to store Terraform state files, rather than using terraform cloud
# Run: ONCE, locally (not via GitHub Actions)
# State: Local terraform.tfstate file (kept on my machine)


terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # NO backend block here! State stays local for bootstrap purpose
}

# Azure provider configuration
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id # From variables.tf
}

# Random strings as provider for unique names
provider "random" {}


# RESOURCES
# Generate random suffix for globally unique storage account name
# Storage account names must be unique across ALL of Azure
resource "random_string" "suffix" {
  length  = 8
  special = false # Only letters and numbers
  upper   = false # Only lowercase
  numeric = true  # Include numbers
}

# Resource Group to hold the storage account
resource "azurerm_resource_group" "tfstate" {
  name     = "rg-terraform-state"
  location = var.location

  tags = {
    purpose     = "terraform-state-backend"
    project     = "3tier-mern-app"
    managed_by  = "terraform"
    environment = "shared"
  }
}

# Storage Account for Terraform state files
# This is Azure's blob storage (like an AWS S3)
resource "azurerm_storage_account" "tfstate" {
  name                = "sttfstate${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.tfstate.name
  location            = var.location

  # Standard tier with Locally Redundant Storage (cheapest)
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Security settings
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  tags = {
    purpose     = "terraform-state"
    project     = "3tier-mern-app"
    managed_by  = "terraform"
    environment = "shared"
  }
}

# Storage Container (like an S3 bucket)
# This will hold all your .tfstate files
resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id # Recommended apprach, account_name is being deprecated
  container_access_type = "private"                          # No public access
}