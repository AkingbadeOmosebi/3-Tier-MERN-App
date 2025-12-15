terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# Reference the resource group created in core-infra
data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = var.vnet_name
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  address_space       = var.vnet_address_space
  
  tags = {
    project     = "3tier-mern-app"
    environment = "production"
    managed_by  = "terraform"
  }
}

# Subnet for AKS nodes
resource "azurerm_subnet" "aks_nodes" {
  name                 = "subnet-aks-nodes"
  resource_group_name  = data.azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Subnet for AKS pods (Azure CNI)
resource "azurerm_subnet" "aks_pods" {
  name                 = "subnet-aks-pods"
  resource_group_name  = data.azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.4.0/22"]
  
  delegation {
    name = "aks-delegation"
    service_delegation {
      name = "Microsoft.ContainerService/managedClusters"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

# Subnet for private endpoints (ACR, Cosmos DB)
resource "azurerm_subnet" "private_endpoints" {
  name                 = "subnet-private-endpoints"
  resource_group_name  = data.azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/25"]
}

# Network Security Group for AKS
resource "azurerm_network_security_group" "aks" {
  name                = "nsg-aks"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  
  tags = {
    project     = "3tier-mern-app"
    environment = "production"
    managed_by  = "terraform"
  }
}

# Associate NSG with AKS nodes subnet
resource "azurerm_subnet_network_security_group_association" "aks_nodes" {
  subnet_id                 = azurerm_subnet.aks_nodes.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

# Private DNS Zone for ACR
resource "azurerm_private_dns_zone" "acr" {
  name                = "privatelink.azurecr.io"
  resource_group_name = data.azurerm_resource_group.main.name
  
  tags = {
    project     = "3tier-mern-app"
    environment = "production"
    managed_by  = "terraform"
  }
}

# Link ACR DNS zone to VNet
resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  name                  = "acr-dns-link"
  resource_group_name   = data.azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.acr.name
  virtual_network_id    = azurerm_virtual_network.main.id
  
  tags = {
    project     = "3tier-mern-app"
    environment = "production"
    managed_by  = "terraform"
  }
}

# Private DNS Zone for Cosmos DB
resource "azurerm_private_dns_zone" "cosmos" {
  name                = "privatelink.mongo.cosmos.azure.com"
  resource_group_name = data.azurerm_resource_group.main.name
  
  tags = {
    project     = "3tier-mern-app"
    environment = "production"
    managed_by  = "terraform"
  }
}

# Link Cosmos DNS zone to VNet
resource "azurerm_private_dns_zone_virtual_network_link" "cosmos" {
  name                  = "cosmos-dns-link"
  resource_group_name   = data.azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.cosmos.name
  virtual_network_id    = azurerm_virtual_network.main.id
  
  tags = {
    project     = "3tier-mern-app"
    environment = "production"
    managed_by  = "terraform"
  }
}