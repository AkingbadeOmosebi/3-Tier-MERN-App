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
}

provider "azuread" {
  # Uses az login credentials automatically
}

# Get current user/client information
data "azurerm_client_config" "current" {}

# Create Azure AD Application
resource "azuread_application" "github_oidc" {
  display_name = "GitHub-OIDC-3Tier-MERN-App"
  owners       = [data.azurerm_client_config.current.object_id]
}

# Create Service Principal for the Application
resource "azuread_service_principal" "github_oidc" {
  client_id = azuread_application.github_oidc.client_id
  owners    = [data.azurerm_client_config.current.object_id]
}

# Create Federated Identity Credential for GitHub Actions
resource "azuread_application_federated_identity_credential" "github_actions" {
  application_id = azuread_application.github_oidc.id
  display_name   = "GitHub-Actions-MERN-App"
  description    = "OIDC for GitHub Actions in 3-Tier-MERN-App repository"

  audiences = ["api://AzureADTokenExchange"]
  issuer    = "https://token.actions.githubusercontent.com"
  subject   = "repo:AkingbadeOmosebi/3-Tier-MERN-App:environment:production"
}

# Create Resource Group for AKS and related resources
resource "azurerm_resource_group" "aks_rg" {
  name     = "rg-3tier-mern-aks"
  location = "West Europe"
}

# Assign Contributor role to the Service Principal for the Resource Group
resource "azurerm_role_assignment" "github_oidc_contributor" {
  scope                = azurerm_resource_group.aks_rg.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.github_oidc.object_id
}

# This references the RG created by my bootstrap module
# Use "data" because we're not creating it, just looking it up
data "azurerm_resource_group" "tfstate" {
  name = "rg-terraform-state"
}

# Grant service principal access to the state storage resource group
resource "azurerm_role_assignment" "github_oidc_tfstate_access" {
  scope                = data.azurerm_resource_group.tfstate.id  # Uses the data source above
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.github_oidc.object_id
}

# Grant subscription-level Contributor access for full infrastructure automation
resource "azurerm_role_assignment" "github_oidc_subscription_contributor" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Owner"
  principal_id         = azuread_service_principal.github_oidc.object_id
}