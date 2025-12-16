# Azure Kubernetes Service (AKS) Cluster

## Overview
I deployed a production-ready AKS cluster for my 3-tier MERN application using Azure CNI networking with separate pod subnets and integrated Azure Container Registry. The cluster provides node-level high availability through multiple nodes across system and user pools.

## Architecture

**Region:** West Europe  
**Kubernetes Version:** 1.33 (community-supported)  
**Networking:** Azure CNI with separate node and pod subnets  
**Node Pools:**
- System Pool: 3 nodes (Standard_B2s)
- User Pool: 3 nodes (Standard_D2s_v3)
- Total: 6 nodes for node-level redundancy

## Prerequisites

- Azure CLI installed and authenticated
- Terraform >= 1.0
- Existing core infrastructure:
  - Resource Group: `rg-3tier-mern-prod`
  - VNet: `vnet-3tier-mern`
  - Subnets: `subnet-aks-nodes`, `subnet-aks-pods`
  - ACR: `acr3TierMernAppAO`
  - Terraform state storage

## Key Configurations

### Network Configuration
- **Network Plugin:** Azure CNI
- **Network Policy:** Azure
- **Service CIDR:** 10.1.0.0/16
- **DNS Service IP:** 10.1.0.10
- **Node Subnet:** subnet-aks-nodes (for node VMs)
- **Pod Subnet:** subnet-aks-pods (for pod IP allocation)

### Security
- System-assigned managed identity
- Azure RBAC enabled
- ACR pull permissions configured via role assignment
- Private cluster networking through VNet integration

### Node Pool Configuration
Both pools configured with:
- Dedicated pod subnet for IP allocation
- 33% max surge during upgrades (minimizes disruption)
- 30GB OS disk (cost-optimized)
- Separate tagging for resource organization

## Deployment

### 1. Initialize Terraform
```bash
terraform init
```

### 2. Review Plan
```bash
terraform plan
```

### 3. Apply Configuration
```bash
terraform apply
```

**Expected deployment time:** 10-15 minutes

### 4. Connect to Cluster
```bash
az aks get-credentials \
  --resource-group rg-3tier-mern-prod \
  --name aks-3tier-mern
```

### 5. Verify Deployment
```bash
kubectl get nodes
kubectl get pods -A
```

## Configuration Files

- `main.tf` - AKS cluster and node pool resources
- `variables.tf` - Configurable parameters
- `backend.tf` - Remote state configuration
- `outputs.tf` - Cluster connection details

## Key Variables
```terraform
kubernetes_version   = "1.33"           # Community-supported version
system_node_count    = 3                # System pool nodes
user_node_count      = 3                # User pool nodes
```

## Issues & Resolutions

### Issue 1: Kubernetes Version Support
**Problem:** Initially configured with Kubernetes 1.29, which had transitioned to LTS-only status requiring Premium tier (6x more expensive than Standard tier).

**Analysis:** Ran `az aks get-versions --location westeurope` and discovered that versions 1.29, 1.30, and 1.31 were only available with `AKSLongTermSupport` plan, requiring Premium tier. The N-2 support policy meant only versions 1.32, 1.33, and 1.34 were available for Standard tier with `KubernetesOfficial` support.

**Solution:** Upgraded to Kubernetes 1.33, which is community-supported within the N-2 window and compatible with Standard tier. Version 1.33 provides a balance between stability (not bleeding edge like 1.34) and modern features.

### Issue 2: Pod Subnet Configuration Inconsistency
**Problem:** User node pool had `pod_subnet_id` configured, but system node pool (default_node_pool) was missing it, causing Azure API error: "All or none of the agentpools should set podsubnet."

**Root Cause:** Azure CNI requires consistent pod subnet configuration across all node pools. Mixing configurations (some pools with pod subnets, some without) is not permitted.

**Solution:** Added `pod_subnet_id` to the system node pool (default_node_pool) to match the user pool configuration. This enables consistent IP management across the cluster with dedicated pod subnet for all pools.

### Issue 3: Multi-AZ Implementation Restrictions
**Problem:** Subscription-level restrictions prevented deployment across multiple availability zones.

**Investigation:** Ran `az vm list-skus` for both Standard_B2s and Standard_D2s_v3 in West Europe, which revealed:
```
Restrictions: NotAvailableForSubscription, type: Zone, locations: westeurope, zones: 3,2
```

**Analysis:** Zones 2 and 3 are restricted for my subscription in West Europe for the required VM SKUs. Only zone 1 is available, which defeats the purpose of multi-AZ deployment (single zone provides no additional redundancy over no zones).

**Decision:** Implemented node-level high availability instead:
- 6 total nodes (3 system + 3 user)
- Kubernetes automatically distributes pods across multiple nodes
- If a node fails, pods reschedule to healthy nodes
- Provides 99.5% availability without zone complexity

**Production Approach:** For production deployment, I would either request zone quota increase via Azure Support, use alternative VM SKUs with zone availability, or consider alternative regions where zones are available for my subscription.

## High Availability Strategy

### Current Implementation: Node-Level Redundancy
I implemented a pragmatic HA approach within subscription constraints:

**System Pool:**
- 3 nodes provide redundancy for Kubernetes system components
- Critical add-ons (CoreDNS, metrics-server) distributed across nodes
- System workload isolation from application workloads

**User Pool:**
- 3 nodes for application workload distribution
- Kubernetes scheduler distributes pods across available nodes
- If a node fails, pods automatically reschedule to healthy nodes

**HA Benefits:**
- Survives individual node failures (hardware, VM issues)
- Automatic pod rescheduling via Kubernetes
- No single point of failure at node level
- Sufficient for 99.5% availability

**Limitations:**
- All nodes potentially in same datacenter (no multi-AZ)
- Vulnerable to datacenter-level failures
- No automatic node-level scaling

**Future Enhancements:**
- Enable multi-AZ when subscription quota is approved
- Implement cluster autoscaler for node-level scaling
- Add Horizontal Pod Autoscaler (HPA) for pod-level scaling
- Consider multiple node pools for workload isolation

## Verification Commands
```bash
# Check cluster status
az aks show --resource-group rg-3tier-mern-prod --name aks-3tier-mern

# List available Kubernetes versions
az aks get-versions --location westeurope --output table

# View node pools
az aks nodepool list --resource-group rg-3tier-mern-prod --cluster-name aks-3tier-mern

# Check node status
kubectl get nodes -o wide

# Verify pod distribution across nodes
kubectl get pods -A -o wide
```

## Outputs

- `kube_config` - Kubernetes configuration (sensitive)
- `cluster_id` - AKS cluster resource ID
- `cluster_name` - AKS cluster name
- `kubelet_identity` - Managed identity object ID for kubelet

## Maintenance

### Upgrade Kubernetes Version
```bash
# Check available upgrades
az aks get-upgrades --resource-group rg-3tier-mern-prod --name aks-3tier-mern

# Perform cluster upgrade
az aks upgrade --resource-group rg-3tier-mern-prod --name aks-3tier-mern --kubernetes-version <version>
```

### Scale Node Pool Manually
```bash
az aks nodepool scale \
  --resource-group rg-3tier-mern-prod \
  --cluster-name aks-3tier-mern \
  --name userpool \
  --node-count <count>
```

### Monitor Cluster Health
```bash
# View cluster metrics
az monitor metrics list \
  --resource <aks-resource-id> \
  --metric "node_cpu_usage_percentage"

# Check cluster diagnostics
az aks show --resource-group rg-3tier-mern-prod --name aks-3tier-mern --query "powerState"
```

## Cost Optimization

- **Tier:** Standard (suitable for production workloads)
- **System Pool:** Standard_B2s (cost-effective for system workloads)
- **User Pool:** Standard_D2s_v3 (balanced compute for applications)
- **Auto-upgrade:** Patch channel enabled (automatic security patches)
- **No zone redundancy:** Avoids zone-related costs and subscription restrictions

**Estimated Monthly Cost:** ~$150-200 for 6 nodes (varies by usage)

## Network Architecture
```
VNet: vnet-3tier-mern (West Europe)
├── subnet-aks-nodes (10.0.1.0/24)
│   └── Node VMs receive IPs from this subnet
└── subnet-aks-pods (10.0.2.0/23)
    └── Pod IPs allocated from this subnet

Service Network: 10.1.0.0/16
└── Internal Kubernetes services use this range
```

## Tags
```
project     = "3tier-mern-app"
environment = "production"
managed_by  = "terraform"
```

## Security Considerations

- Cluster uses system-assigned managed identity (no credential management)
- RBAC enabled at both Kubernetes and Azure levels
- ACR integration secured via role assignments
- Pod subnet provides network-level isolation
- Private cluster configuration for enhanced security

## Author
Infrastructure as Code managed via Terraform by Akingbade Omosebi