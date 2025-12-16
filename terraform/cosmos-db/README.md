# Azure Cosmos DB for MongoDB

## Overview
I deployed a serverless Cosmos DB instance with MongoDB API for my 3-tier MERN application backend. The database is configured with private endpoint access for security and automated periodic backups. Due to Azure Cosmos DB Serverless limitations, the deployment uses a single region configuration.

## Architecture

**Region:** North Europe  
**API:** MongoDB 4.2  
**Capacity Mode:** Serverless  
**Database:** merndb  
**Access:** Private endpoint only  
**Replication:** Single region (Serverless limitation)

## Prerequisites

- Azure CLI installed and authenticated
- Terraform >= 1.0
- Existing core infrastructure:
  - Resource Group: `rg-3tier-mern-prod`
  - VNet: `vnet-3tier-mern`
  - Subnet: `subnet-private-endpoints`
  - Private DNS Zone: `privatelink.mongo.cosmos.azure.com`
  - Terraform state storage

## Key Configurations

### Database Settings
- **MongoDB Version:** 4.2
- **Consistency Level:** Session (balance between consistency and performance)
- **Capacity Mode:** Serverless (pay-per-use, ideal for variable workloads)
- **Backup Type:** Periodic
  - Interval: 4 hours
  - Retention: 7 days

### Security
- **Public Network Access:** Disabled (private endpoint only)
- **Private Endpoint:** Enabled (connected to West Europe VNet)
- **Private DNS Integration:** Configured for seamless name resolution
- **Connection Method:** Private endpoint through VNet

### High Availability
- **Region Configuration:** Single region (North Europe)
- **Zone Redundancy:** Disabled (cost optimization + regional capacity constraints)
- **Replication:** None (Serverless accounts do not support multi-region)
- **Backup Strategy:** Periodic backups with 7-day retention

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

**Expected deployment time:** 12-20 minutes

### 4. Retrieve Connection String
```bash
terraform output -raw cosmos_connection_string
```

## Configuration Files

- `main.tf` - Cosmos DB account, database, and private endpoint configuration
- `variables.tf` - Configurable parameters
- `backend.tf` - Remote state configuration
- `outputs.tf` - Connection details and credentials

## Key Variables
```terraform
location              = "North Europe"
cosmos_account_name   = "cosmos-3tier-mern-ao"
cosmos_database_name  = "merndb"
```

## Issues & Resolutions

### Issue 1: Regional Capacity Constraints (East US)
**Problem:** Initial deployment to East US region failed with error:
```
"Sorry, we are currently experiencing high demand in East US region for the zonal redundant (Availability Zones) accounts"
```

**Analysis:** Azure Cosmos DB Serverless has limited regional capacity. East US was experiencing high demand and could not provision new Serverless accounts, even without zone redundancy explicitly enabled.

**Solution:** Changed deployment region to West Europe to avoid capacity constraints.

### Issue 2: Regional Capacity Constraints (West Europe)
**Problem:** Deployment to West Europe also failed with similar capacity error:
```
"Sorry, we are currently experiencing high demand in West Europe region"
```

**Analysis:** West Europe also experiencing capacity constraints for Cosmos DB Serverless. This revealed a pattern of limited Serverless availability across major regions.

**Solution:** Changed primary region to North Europe, which had available capacity and successfully deployed.

### Issue 3: Invalid MongoDB Version Syntax
**Problem:** Initial configuration used `MongoDBv4.2` as a capability, resulting in Terraform validation error:
```
expected capabilities.2.name to be one of [...], got MongoDBv4.2
```

**Root Cause:** MongoDB version in Cosmos DB is not specified via capabilities. The `MongoDBv4.2` capability name does not exist in the Terraform azurerm provider.

**Solution:** Used the correct attribute `mongo_server_version = "4.2"` as a top-level attribute in the `azurerm_cosmosdb_account` resource, not as a capability.

**Correct Configuration:**
```terraform
resource "azurerm_cosmosdb_account" "main" {
  mongo_server_version = "4.2"
  
  capabilities {
    name = "EnableServerless"
  }
  
  capabilities {
    name = "EnableMongo"
  }
}
```

### Issue 4: Serverless Multi-Region Limitation
**Problem:** Attempted to add secondary region (West Europe) for high availability but received error:
```
"Serverless accounts do not support multiple regions"
```

**Root Cause:** Azure Cosmos DB Serverless has a platform limitation that restricts deployments to a single region only. Multi-region replication requires Provisioned Throughput mode.

**Analysis:** To enable multi-region, I would need to:
- Remove `EnableServerless` capability
- Switch to Provisioned Throughput mode
- Configure minimum 400 RU/s throughput
- Accept approximately 6x increase in monthly cost (from $10-20 to $48+)

**Decision:** Chose to remain with Serverless single-region deployment because:
- Cost-effective for portfolio project demonstration
- Pay-per-use model ideal for variable demo traffic
- Sufficient for showcasing infrastructure concepts
- AKS already provides node-level high availability

**Production Recommendation:** For production workloads requiring region-level disaster recovery, use Provisioned Throughput mode to enable multi-region replication.

## High Availability Strategy

### Current Configuration: Single Region
I deployed Cosmos DB in single-region mode due to Serverless platform limitations:

**Region: North Europe**
- Handles all read and write operations
- Single point of failure at region level
- No automatic regional failover capability
- Relies on periodic backups for disaster recovery

**HA Limitations:**
- No protection against regional outages
- No automatic failover capability
- Recovery requires manual restoration from backup
- Potential data loss up to 4 hours (backup interval)

**Compensating Controls:**
- Periodic backups every 4 hours
- 7-day backup retention
- Point-in-time restore capability
- AKS provides compute-layer high availability (6 nodes)

### Why Single Region

**Platform Constraint:**
Azure Cosmos DB Serverless does not support multi-region replication. This is a hard platform limitation that cannot be worked around while using Serverless mode.

**Cost-Benefit Analysis:**
To achieve multi-region high availability, I would need to switch to Provisioned Throughput:
- Minimum cost: $48/month (400 RU/s × 2 regions)
- Current Serverless cost: $10-20/month
- 3-5x cost increase for portfolio project

**Decision Rationale:**
For a portfolio demonstration project, single-region Serverless provides the best balance of:
- Cost efficiency (pay-per-use)
- Feature demonstration (MongoDB API, private endpoints, IaC)
- Sufficient availability for non-production use

**Production Alternative:**
For production workloads requiring regional disaster recovery, I would implement:
```terraform
resource "azurerm_cosmosdb_account" "main" {
  # Remove EnableServerless capability
  
  capabilities {
    name = "EnableMongo"
  }
  
  # Add multiple regions
  geo_location {
    location          = "North Europe"
    failover_priority = 0
  }
  
  geo_location {
    location          = "West Europe"
    failover_priority = 1
  }
}

# Add provisioned throughput to database
resource "azurerm_cosmosdb_mongo_database" "main" {
  throughput = 400  # Minimum RU/s
}
```

## Cross-Region Architecture

**Note:** Cosmos DB is in North Europe, AKS cluster is in West Europe.
```
NORTH EUROPE:
└── Cosmos DB (Single Region)
    ├── Read + Write operations
    ├── Private endpoint connection to West Europe VNet
    └── No replication

WEST EUROPE:
└── AKS Cluster (6 nodes)
    └── Connects to Cosmos DB via private endpoint
```

**Latency Considerations:**
- West Europe AKS → North Europe Cosmos: ~25ms
- Acceptable for portfolio and most production workloads
- Optimized by private endpoint (no public internet routing)
- Traffic stays within Azure backbone network

## Verification Commands
```bash
# Check Cosmos DB account
az cosmosdb show \
  --name <cosmos-account-name> \
  --resource-group rg-3tier-mern-prod

# Verify single region configuration
az cosmosdb show \
  --name <cosmos-account-name> \
  --resource-group rg-3tier-mern-prod \
  --query "locations[].{Region:locationName, FailoverPriority:failoverPriority}"

# List connection strings
az cosmosdb keys list \
  --name <cosmos-account-name> \
  --resource-group rg-3tier-mern-prod \
  --type connection-strings

# Verify MongoDB database
az cosmosdb mongodb database show \
  --account-name <cosmos-account-name> \
  --name merndb \
  --resource-group rg-3tier-mern-prod

# Check private endpoint
az network private-endpoint show \
  --name <private-endpoint-name> \
  --resource-group rg-3tier-mern-prod

# Check capacity mode (should show Serverless)
az cosmosdb show \
  --name <cosmos-account-name> \
  --resource-group rg-3tier-mern-prod \
  --query "capabilities[?name=='EnableServerless']"
```

## Outputs

- `cosmos_account_name` - Cosmos DB account name
- `cosmos_endpoint` - MongoDB endpoint URL
- `cosmos_database_name` - Database name (merndb)
- `cosmos_primary_key` - Primary access key (sensitive)
- `cosmos_connection_string` - Full MongoDB connection string (sensitive)
- `private_endpoint_ip` - Private endpoint IP address in West Europe VNet

## Connection String Format
```
mongodb://<account-name>:<primary-key>@<account-name>.mongo.cosmos.azure.com:10255/?ssl=true&replicaSet=globaldb&retrywrites=false&maxIdleTimeMS=120000&appName=@<account-name>@
```

## Application Integration

### Node.js/Express Backend Example
```javascript
const mongoose = require('mongoose');

const connectionString = process.env.COSMOS_CONNECTION_STRING;

mongoose.connect(connectionString, {
  useNewUrlParser: true,
  useUnifiedTopology: true,
  ssl: true,
  retryWrites: false
})
.then(() => console.log('Connected to Cosmos DB'))
.catch(err => console.error('Connection error:', err));
```

### Kubernetes Secret Configuration
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cosmos-db-secret
type: Opaque
stringData:
  connection-string: <cosmos-connection-string>
```

### Environment Variable
```bash
export COSMOS_CONNECTION_STRING=$(terraform output -raw cosmos_connection_string)
```

## Maintenance

### Backup Management
Backups are automated with no manual intervention required:
- **Type:** Periodic (point-in-time restore available)
- **Frequency:** Every 4 hours
- **Retention:** 7 days
- **Storage:** Azure-managed backup storage

### Restore from Backup
```bash
# List available restore timestamps
az cosmosdb restorable-database-account list \
  --account-name <cosmos-account-name>

# Restore to specific point in time
az cosmosdb restore \
  --resource-group rg-3tier-mern-prod \
  --account-name <cosmos-account-name> \
  --restore-timestamp <timestamp-utc> \
  --target-database-account-name <new-account-name>
```

### Monitor Usage and Performance
```bash
# View request unit consumption
az monitor metrics list \
  --resource <cosmos-resource-id> \
  --metric TotalRequestUnits \
  --aggregation Total

# Check storage usage
az monitor metrics list \
  --resource <cosmos-resource-id> \
  --metric DataUsage \
  --aggregation Average

# View consistency policy
az cosmosdb show \
  --name <cosmos-account-name> \
  --resource-group rg-3tier-mern-prod \
  --query "consistencyPolicy"
```

## Cost Optimization

- **Serverless Mode:** Pay only for request units (RUs) consumed and storage used
- **No Provisioned Throughput:** No minimum charges when idle
- **Single Region:** Reduced cost compared to multi-region
- **Periodic Backup:** More cost-effective than continuous backup

**Estimated Monthly Cost:**
- Serverless single region: $5-20 (depending on usage)
- Cost scales with actual usage (RU consumption + storage)
- No charges when database is idle

**Cost Comparison:**
- Serverless (current): $5-20/month
- Provisioned single region: $24/month minimum
- Provisioned multi-region: $48/month minimum

## Network Security
```
Private Endpoint Flow:
AKS Pod → Private Endpoint → Cosmos DB (Private IP)
   ↓
No public internet traversal
   ↓
Traffic stays within Azure backbone
```

**Security Benefits:**
- No exposure to public internet
- Traffic encrypted via SSL/TLS
- Private DNS resolution within VNet
- Integration with Azure Private Link

## Tags
```
project     = "3tier-mern-app"
environment = "production"
managed_by  = "terraform"
```

## Security Best Practices

- Store connection strings in Azure Key Vault or Kubernetes Secrets (never in code)
- Use Terraform output with `-raw` flag to retrieve sensitive values
- Rotate access keys regularly (recommended: every 90 days)
- Enable Azure Defender for Cosmos DB in production environments
- Monitor access patterns via Azure Monitor and diagnostic logs
- Use role-based access control (RBAC) for management plane operations

## Disaster Recovery Considerations

**Current DR Capabilities:**
- **Backup-based recovery only** (no automatic regional failover)
- **Recovery Time Objective (RTO):** 1-2 hours (manual restore process)
- **Recovery Point Objective (RPO):** Up to 4 hours (backup interval)

**Disaster Recovery Process:**
1. Detect service disruption in North Europe
2. Create support ticket with Azure
3. Request point-in-time restore from backup
4. Restore to new Cosmos DB account
5. Update application connection strings
6. Validate data integrity
7. Resume operations

**Limitations:**
- No automatic failover
- Requires manual intervention
- Potential data loss up to 4 hours
- Downtime during restore process

**Production Recommendation:**
For production workloads requiring minimal RTO/RPO:
- Use Provisioned Throughput mode
- Enable multi-region replication
- Configure automatic failover
- Achieve RTO: <1 minute, RPO: <5 seconds

## Author
Infrastructure as Code managed via Terraform by Akingbade Omosebi