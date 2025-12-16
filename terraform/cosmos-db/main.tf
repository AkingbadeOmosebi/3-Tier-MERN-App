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
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# Reference existing resources
data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

data "azurerm_subnet" "private_endpoints" {
  name                 = "subnet-private-endpoints"
  virtual_network_name = "vnet-3tier-mern"
  resource_group_name  = var.resource_group_name
}

data "azurerm_private_dns_zone" "cosmos" {
  name                = "privatelink.mongo.cosmos.azure.com"
  resource_group_name = var.resource_group_name
}

# Random suffix for unique Cosmos account name
resource "random_string" "cosmos_suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Cosmos DB Account (MongoDB API)
resource "azurerm_cosmosdb_account" "main" {
  name                = "${var.cosmos_account_name}-${random_string.cosmos_suffix.result}"
  location            = var.location_primary  # updated the name to match corresponding variable
  resource_group_name = data.azurerm_resource_group.main.name
  offer_type          = "Standard"
  kind                = "MongoDB"

  # MongoDB server version
  mongo_server_version = "4.2"

  # Serverless capacity mode
  capabilities {
    name = "EnableServerless"
  }

  # MongoDB API type
  capabilities {
    name = "EnableMongo"
  }

  # Consistency level
  consistency_policy {
    consistency_level = "Session"
  }

  # Primary region with zone redundancy
  geo_location {
    location          = var.location_primary
    failover_priority = 0
    zone_redundant    = false  # # Initially designed for zone redundancy, but disabled as most EU regions had capacity issues
  }

  # Disable public network access (private endpoint only)
  public_network_access_enabled = false

  # Continuous backup
  backup {
    type                = "Periodic"
    interval_in_minutes = 240  # 4 hours
    retention_in_hours  = 168  # 7 days
    
  }

  tags = {
    project     = "3tier-mern-app"
    environment = "production"
    managed_by  = "terraform"
  }
}

# MongoDB Database
resource "azurerm_cosmosdb_mongo_database" "main" {
  name                = var.cosmos_database_name
  resource_group_name = data.azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
}

# Private Endpoint for Cosmos DB
resource "azurerm_private_endpoint" "cosmos" {
  name                = "pe-cosmos-${random_string.cosmos_suffix.result}"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  subnet_id           = data.azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "psc-cosmos"
    private_connection_resource_id = azurerm_cosmosdb_account.main.id
    is_manual_connection           = false
    subresource_names              = ["MongoDB"]
  }

  private_dns_zone_group {
    name                 = "cosmos-dns-zone-group"
    private_dns_zone_ids = [data.azurerm_private_dns_zone.cosmos.id]
  }

  tags = {
    project     = "3tier-mern-app"
    environment = "production"
    managed_by  = "terraform"
  }
}