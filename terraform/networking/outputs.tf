output "vnet_id" {
  description = "Virtual network ID"
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Virtual network name"
  value       = azurerm_virtual_network.main.name
}

output "aks_nodes_subnet_id" {
  description = "AKS nodes subnet ID"
  value       = azurerm_subnet.aks_nodes.id
}

output "aks_pods_subnet_id" {
  description = "AKS pods subnet ID"
  value       = azurerm_subnet.aks_pods.id
}

output "private_endpoints_subnet_id" {
  description = "Private endpoints subnet ID"
  value       = azurerm_subnet.private_endpoints.id
}

output "acr_private_dns_zone_id" {
  description = "ACR private DNS zone ID"
  value       = azurerm_private_dns_zone.acr.id
}

output "cosmos_private_dns_zone_id" {
  description = "Cosmos DB private DNS zone ID"
  value       = azurerm_private_dns_zone.cosmos.id
}