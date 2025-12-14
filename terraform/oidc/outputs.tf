output "client_id" {
  description = "Application (client) ID for GitHub Actions"
  value       = azuread_application.github_oidc.client_id
}

output "tenant_id" {
  description = "Azure Tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  description = "Azure Subscription ID"
  value       = data.azurerm_client_config.current.subscription_id
}