# Networking module variables

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
  sensitive   = true
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "West Europe"
}

variable "resource_group_name" {
  description = "Resource group for networking resources"
  type        = string
  default     = "rg-3tier-mern-prod"
}

variable "vnet_name" {
  description = "Virtual network name"
  type        = string
  default     = "vnet-3tier-mern"
}

variable "vnet_address_space" {
  description = "VNet address space"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}
