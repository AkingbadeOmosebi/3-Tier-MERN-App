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

data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

data "azurerm_subnet" "aks_nodes" {
  name                 = "subnet-aks-nodes"
  virtual_network_name = "vnet-3tier-mern"
  resource_group_name  = var.resource_group_name
}

data "azurerm_subnet" "aks_pods" {
  name                 = "subnet-aks-pods"
  virtual_network_name = "vnet-3tier-mern"
  resource_group_name  = var.resource_group_name
}

data "azurerm_container_registry" "acr" {
  name                = "acr3TierMernAppAO"
  resource_group_name = var.resource_group_name
}

resource "azurerm_kubernetes_cluster" "main" {
  name                      = var.cluster_name
  location                  = data.azurerm_resource_group.main.location
  resource_group_name       = data.azurerm_resource_group.main.name
  dns_prefix                = "${var.cluster_name}-dns"
  kubernetes_version        = var.kubernetes_version
  automatic_upgrade_channel = "patch"
  sku_tier                  = "Standard"
  
  default_node_pool {  # due to regional capacity constraints, i will let Azure place nodes where capacity is available
    name                         = "systempool"
    node_count                   = var.system_node_count
    vm_size                      = "Standard_B2s"
    os_disk_size_gb              = 30
    vnet_subnet_id               = data.azurerm_subnet.aks_nodes.id
    pod_subnet_id                = data.azurerm_subnet.aks_pods.id
    only_critical_addons_enabled = true
    
    upgrade_settings {
      max_surge = "33%"
    }
    
    tags = {
      purpose     = "system-workloads"
      project     = "3tier-mern-app"
      environment = "production"
    }
  }
  
  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
    service_cidr   = "10.1.0.0/16"
    dns_service_ip = "10.1.0.10"
  }
  
  identity {
    type = "SystemAssigned"
  }
  
  role_based_access_control_enabled = true
  
  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = data.azurerm_client_config.current.tenant_id
  }
  
  tags = {
    project     = "3tier-mern-app"
    environment = "production"
    managed_by  = "terraform"
  }
}

# No zones here due to capacity constraints, i will let Azure place nodes where capacity is available
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "userpool"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = "Standard_D2s_v3"
  node_count            = 3
  os_disk_size_gb       = 30
  vnet_subnet_id        = data.azurerm_subnet.aks_nodes.id
  pod_subnet_id         = data.azurerm_subnet.aks_pods.id
  
  upgrade_settings {
    max_surge = "33%"
  }
  
  tags = {
    purpose     = "user-workloads"
    project     = "3tier-mern-app"
    environment = "production"
  }
}

resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = data.azurerm_container_registry.acr.id
  skip_service_principal_aad_check = true
}