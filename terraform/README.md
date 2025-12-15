# 3-Tier MERN Application - Infrastructure Documentation

## Overview

Production-grade infrastructure deployment for a 3-tier MERN (MongoDB, Express, React, Node.js) application on Azure Kubernetes Service, implemented using Infrastructure as Code principles with Terraform and automated via GitHub Actions.

## Architecture

### Infrastructure Components

**Compute & Orchestration:**
- Azure Kubernetes Service (AKS) - Multi-availability zone cluster
- 3-node system pool (Kubernetes infrastructure)
- 3-node user pool (application workloads)
- Auto-scaling capabilities (3-10 nodes)

**Container Management:**
- Azure Container Registry (ACR) - Private container image storage
- Private endpoint connectivity (no public internet access)
- OIDC-based authentication for GitHub Actions
- Least-privilege RBAC (AcrPush role)

**Networking:**
- Virtual Network (10.0.0.0/16 address space)
- Segmented subnets for isolation:
  - AKS nodes subnet (10.0.1.0/24)
  - AKS pods subnet (10.0.4.0/22) with Azure CNI delegation
  - Private endpoints subnet (10.0.2.0/25)
- Network Security Groups for traffic control
- Private DNS zones for internal name resolution

**Data Layer:**
- Cosmos DB with MongoDB API (serverless capacity mode)
- Private endpoint for VNet-only access
- Session consistency level for web application requirements
- Continuous backup with 7-day retention

**State Management:**
- Azure Blob Storage for Terraform remote state
- State isolation per module (foundation, networking, aks, data)
- Centralized state backend for team collaboration

## Module Structure
```
terraform/
├── bootstrap/      # State backend infrastructure (one-time setup)
├── oidc/          # GitHub Actions authentication
├── core-infra/    # ACR and resource groups
├── networking/    # VNet, subnets, NSGs, private DNS
├── aks-cluster/   # Kubernetes cluster configuration
└── cosmos-db/     # MongoDB-compatible database
```

## Deployment Order

Infrastructure modules have explicit dependencies and must be deployed sequentially:

1. **bootstrap** - Creates Azure Storage Account for Terraform state
2. **oidc** - Establishes federated identity for GitHub Actions (passwordless authentication)
3. **core-infra** - Provisions ACR and primary resource group
4. **networking** - Creates VNet, subnets, and DNS infrastructure
5. **aks-cluster** - Deploys Kubernetes cluster (depends on networking)
6. **cosmos-db** - Provisions database with private connectivity (depends on networking)

## Security Implementation

### Network Security

**Private Endpoints:**
- All Azure PaaS services accessed via private endpoints
- No public internet exposure for ACR or Cosmos DB
- Traffic remains on Microsoft backbone network

**Network Segmentation:**
- Isolated subnets for different workload tiers
- Network Security Groups enforce least-privilege access
- Azure CNI provides pod-level network policies

### Authentication & Authorization

**OIDC Integration:**
- GitHub Actions authenticates to Azure without stored credentials
- Short-lived tokens based on workflow identity
- Federated identity credential tied to specific repository and branch

**RBAC:**
- Service principals granted minimum required permissions
- ACR access limited to push/pull operations
- No admin credentials enabled on ACR

### Infrastructure as Code

**State Management:**
- Remote state in Azure Blob Storage
- State locking prevents concurrent modifications
- Encrypted at rest with Azure Storage encryption

## Technical Decisions

### Resource Naming Convention

Resources follow Azure naming best practices with descriptive prefixes:
- Resource groups: `rg-`
- Virtual networks: `vnet-`
- Subnets: `subnet-`
- Network security groups: `nsg-`
- Private endpoints: `pe-`

### Cost Optimization

**Serverless Cosmos DB:**
- Pay-per-request pricing model
- No provisioned capacity charges when idle
- Suitable for variable workloads and development environments

**AKS Node Sizing:**
- B-series VMs for system pool (cost-effective for cluster services)
- D-series VMs for user pool (balanced compute for applications)
- Auto-scaling reduces costs during low-traffic periods

### High Availability

**Multi-AZ Configuration:**
- AKS nodes distributed across availability zones 1, 2, 3
- Survives datacenter-level failures
- Application pods scheduled with anti-affinity rules

**Consistency Model:**
- Session consistency for Cosmos DB
- Users see their own writes immediately
- Optimal balance between consistency and performance for web applications

## Known Limitations

**Regional Capacity Constraints:**
During initial deployment, zone-redundant Cosmos DB provisioning encountered capacity limitations in West Europe, North Europe, and UK South regions. This is an Azure platform constraint rather than a configuration issue. The infrastructure code supports zone redundancy and can be enabled when regional capacity is available.

## Deployment Process

### Local Prerequisites

- Terraform >= 1.0
- Azure CLI authenticated (`az login`)
- Subscription ID configured in environment variables

### Bootstrap Execution
```bash
cd terraform/bootstrap
export TF_VAR_subscription_id="<subscription-id>"
terraform init
terraform fmt
terraform validate
terraform apply
```

Save the storage account name from outputs for subsequent modules.

### Module Deployment

Each module follows the same pattern:
```bash
cd terraform/<module-name>
export TF_VAR_subscription_id="<subscription-id>"
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

### GitHub Actions Integration

Automated deployment planned with:
- tfsec security scanning
- Infracost cost estimation
- Automated terraform plan on pull requests
- Automated apply on merge to main branch

## Future Enhancements

**Planned:**
- GitHub Actions workflow for automated infrastructure deployment
- AKS cluster with production-grade configuration
- GitOps implementation with ArgoCD
- NGINX Ingress Controller with TLS termination
- Custom DNS configuration with cert-manager
- Sealed Secrets for sensitive data management
- Prometheus and Grafana for observability

**Under Consideration:**
- Azure Application Gateway with WAF
- Multi-region deployment for disaster recovery
- Azure Monitor integration for centralized logging

## Maintenance

### State Backend

The bootstrap storage account contains state for all modules. Do not delete this resource group without first migrating or backing up state files.

### Destroying Infrastructure

Modules must be destroyed in reverse order:
1. cosmos-db
2. aks-cluster
3. networking
4. core-infra

Do not destroy oidc or bootstrap unless fully decommissioning the project.

## Contact

For questions regarding this my repo infrastructure implementation, feel free to reach out to me. 