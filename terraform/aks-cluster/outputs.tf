
# OUTPUTS - Important Values for Later Use

# These values are needed by:
# - kubectl to connect to the cluster
# - ArgoCD for GitOps deployment
# - Other modules that interact with AKS


output "cluster_name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.main.name
}

output "cluster_id" {
  description = "AKS cluster resource ID"
  value       = azurerm_kubernetes_cluster.main.id
}

output "kube_config" {
  description = "Kubernetes config for kubectl (sensitive)"
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive   = true
}

output "cluster_fqdn" {
  description = "Kubernetes API server FQDN"
  value       = azurerm_kubernetes_cluster.main.fqdn
}

output "kubelet_identity_object_id" {
  description = "Object ID of kubelet managed identity (for additional RBAC)"
  value       = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

output "node_resource_group" {
  description = "Auto-created resource group for cluster resources (load balancers, disks, etc.)"
  value       = azurerm_kubernetes_cluster.main.node_resource_group
}