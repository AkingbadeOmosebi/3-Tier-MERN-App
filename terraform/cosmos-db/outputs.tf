output "cosmos_account_name" {
  description = "Cosmos DB account name"
  value       = azurerm_cosmosdb_account.main.name
}

output "cosmos_endpoint" {
  description = "Cosmos DB MongoDB endpoint"
  value       = azurerm_cosmosdb_account.main.endpoint
}

output "cosmos_database_name" {
  description = "MongoDB database name"
  value       = azurerm_cosmosdb_mongo_database.main.name
}

output "cosmos_primary_key" {
  description = "Cosmos DB primary master key"
  value       = azurerm_cosmosdb_account.main.primary_key
  sensitive   = true
}

output "cosmos_connection_string" {
  description = "MongoDB connection string (constructed)"
  value       = "mongodb://${azurerm_cosmosdb_account.main.name}:${azurerm_cosmosdb_account.main.primary_key}@${azurerm_cosmosdb_account.main.name}.mongo.cosmos.azure.com:10255/?ssl=true&replicaSet=globaldb&retrywrites=false&maxIdleTimeMS=120000&appName=@${azurerm_cosmosdb_account.main.name}@"
  sensitive   = true
}

output "private_endpoint_ip" {
  description = "Private endpoint IP address"
  value       = azurerm_private_endpoint.cosmos.private_service_connection[0].private_ip_address
}