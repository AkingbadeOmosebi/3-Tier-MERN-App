terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

provider "azuread" {}

# Gets the GitHub OIDC service principal
data "azuread_service_principal" "github_oidc" {
  display_name = "GitHub-OIDC-3Tier-MERN-App"
}

# Create resource group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  
  tags = {
    project     = "3tier-mern-app"
    environment = "production"
    managed_by  = "terraform"
  }
}

# Create Azure Container Registry
resource "azurerm_container_registry" "acr" {
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = false
  
  tags = {
    project     = "3tier-mern-app"
    environment = "production"
    managed_by  = "terraform"
  }
}

# Give GitHub OIDC permission to push images
resource "azurerm_role_assignment" "acr_push" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPush"
  principal_id         = data.azuread_service_principal.github_oidc.object_id
}

# Grant GitHub OIDC service principal Contributor access to this resource group
# This allows GitHub Actions to manage resources within this RG
resource "azurerm_role_assignment" "github_oidc_rg_access" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Contributor"
  principal_id         = data.azuread_service_principal.github_oidc.object_id
}


# Trigger test# Trigger deployment!
