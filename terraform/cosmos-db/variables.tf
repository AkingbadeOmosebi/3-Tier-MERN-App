variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
  sensitive   = true
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "East US"  # # Initially designed for zone redundancy, but disabled as most EU regions had capacity issues
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
  default     = "rg-3tier-mern-prod"
}

variable "cosmos_account_name" {
  description = "Cosmos DB account name (globally unique)"
  type        = string
  default     = "cosmos-3tier-mern-ao"
}

variable "cosmos_database_name" {
  description = "Database name for MERN app"
  type        = string
  default     = "merndb"
}