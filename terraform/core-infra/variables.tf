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
  description = "Main resource group name"
  type        = string
  default     = "rg-3tier-mern-prod"
}

variable "acr_name" {
  description = "Container registry name"
  type        = string
  default     = "acr3TierMernAppAO"
}