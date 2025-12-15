variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
  sensitive   = true # Won't show in logs
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "West Europe"
}