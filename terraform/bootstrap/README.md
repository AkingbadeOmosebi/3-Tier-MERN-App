# Terraform Bootstrap

## Purpose
Creates Azure Storage Account for storing Terraform state files for all other modules.

## Why Bootstrap Exists
This solves the "chicken-egg" problem:
- We want Terraform state in Azure Storage
- But we need Terraform to create the storage account
- So where does the storage account's state go?
- Answer: Keep it local (this is the exception)

## Run This ONCE
```bash
# Set subscription
export ARM_SUBSCRIPTION_ID="SUBSCRIPTION_ID_HERE"

# Initialize Terraform
terraform init

# Preview what will be created
terraform plan

# Create the resources
terraform apply
```

## After Running
1. Save the `storage_account_name` from outputs
2. Add it to other modules' backend configuration
3. DO NOT run `terraform destroy` unless you want to lose all state!

## State File Location
The state file for this module stays LOCAL:
- `terraform.tfstate` (in this directory)
- Do NOT commit this to Git (it's in .gitignore)
- Optionally backup this file somewhere safe

## Cost
Approximately $0.02 per day (~$0.60/month)