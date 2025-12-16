# VARIABLES - Configuration Inputs
# These allow the module to be flexible and reusable
# Values can be overridden via terraform.tfvars or environment variables

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
  sensitive   = true # Won't show in logs
}

variable "location" {
  description = "Azure region for AKS cluster"
  type        = string
  default     = "West Europe"
}

variable "resource_group_name" {
  description = "Resource group containing networking resources"
  type        = string
  default     = "rg-3tier-mern-prod"
}

variable "cluster_name" {
  description = "AKS cluster name"
  type        = string
  default     = "aks-3tier-mern"
}

variable "kubernetes_version" {
  description = "Kubernetes version (use 'az aks get-versions --location westeurope' to see available)"
  type        = string
  default     = "1.33" # Stable, well-tested community-supported version
}

variable "system_node_count" {
  description = "Number of nodes in system pool (Kubernetes infrastructure)"
  type        = number
  default     = 3 # One per each availability zone (3 zones total)
}

variable "user_node_count" {
  description = "Initial number of nodes in user pool (your applications)"
  type        = number
  default     = 3 # One per each availability zone (3 zones total)
}

variable "user_node_min_count" {
  description = "Minimum nodes for auto-scaling"
  type        = number
  default     = 3 # One per each availability zone (3 zones total)
}

variable "user_node_max_count" {
  description = "Maximum nodes for auto-scaling"
  type        = number
  default     = 6 # Allows scaling up to 2 per zone, total 6. 2x3 zones
}