# CI/CD Pipeline for Azure Infrastructure

## Overview

I implemented a comprehensive CI/CD pipeline using GitHub Actions to automate the deployment, validation, and management of my Azure infrastructure. The pipeline includes security scanning with Checkov, cost estimation with Infracost, and automated deployment with manual approval gates for production environments.

## Architecture

The pipeline manages four Terraform modules in sequential order:
1. **Networking** - VNet, subnets, NSGs, and private DNS zones
2. **Core Infrastructure** - Resource group and Azure Container Registry
3. **AKS Cluster** - Kubernetes cluster with node pools
4. **Cosmos DB** - MongoDB API with multi-region configuration

## Workflows

### 1. terraform-deploy.yml (Main Deployment)

**Trigger:** Push to `main` branch  
**Purpose:** Deploy infrastructure to production with security and cost validation

**Pipeline Stages:**

**Security Scanning (10 minutes)**
- Runs Checkov against all Terraform modules
- Fails deployment if critical security issues detected
- Excludes OIDC folder from scanning

**Cost Estimation (15 minutes)**
- Analyzes all modules with Infracost
- Generates cost estimates before deployment
- Posts detailed breakdown to workflow summary
- Runs in parallel for all modules

**Deployment (60 minutes)**
- Requires manual approval via GitHub Environment protection
- Deploys modules sequentially to respect dependencies
- Uses OIDC for keyless Azure authentication
- Fails fast if any module deployment fails

**Notification (5 minutes)**
- Creates GitHub issue with deployment status
- Tags issues with appropriate labels
- Includes workflow run links and timestamps
- Mentions triggering user for failures

### 2. terraform-pr.yml (Pull Request Validation)

**Trigger:** Pull request to `main` branch  
**Purpose:** Validate changes without deploying

**Pipeline Stages:**

**Security Scanning (10 minutes)**
- Validates Terraform code security before merge
- Provides early feedback in PR

**Cost Estimation (15 minutes)**
- Shows cost impact of proposed changes
- Posts estimates as PR comments
- Updates existing comments on subsequent pushes

**Validation (20 minutes)**
- Runs `terraform validate` on all modules
- Generates plan to show what would change
- Posts plan output as PR comments
- Does not deploy anything

### 3. terraform-destroy.yml (Manual Destruction)

**Trigger:** Manual workflow dispatch only  
**Purpose:** Safely destroy infrastructure with confirmation

**Required Inputs:**
- Confirmation text: Must type "destroy" exactly
- Modules: Select specific modules or "all"

**Pipeline Stages:**

**Input Validation (2 minutes)**
- Verifies confirmation text matches "destroy"
- Fails workflow if confirmation incorrect

**Destruction (90 minutes)**
- Requires manual approval via Environment protection
- Destroys modules in reverse dependency order
- Can target specific modules or all infrastructure

**Notification (5 minutes)**
- Creates GitHub issue documenting destruction
- Records who triggered destruction and when
- Includes workflow run link for audit trail

## Prerequisites

### GitHub Secrets

The following secrets must be configured in repository settings:
```
AZURE_CLIENT_ID          - OIDC service principal application ID
AZURE_TENANT_ID          - Azure Active Directory tenant ID
AZURE_SUBSCRIPTION_ID    - Target Azure subscription ID
INFRACOST_API_KEY        - Infracost API key for cost estimation
```

### GitHub Environment

A `production` environment must be configured with:
- Required reviewers enabled
- At least one reviewer added
- Protection rules saved

### Terraform Backend

All modules must use remote backend in Azure Storage:
```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "sttfstatem9dyyto8"
    container_name       = "tfstate"
    key                  = "<module-name>.tfstate"
  }
}
```

## Usage

### Deploying Infrastructure

**Via Pull Request (Recommended):**

1. Create feature branch:
```bash
git checkout -b feature/infrastructure-update
```

2. Make Terraform changes in appropriate module

3. Commit and push:
```bash
git add .
git commit -m "Update infrastructure configuration"
git push origin feature/infrastructure-update
```

4. Create pull request to `main` branch

5. Review automated checks:
   - Security scan results
   - Cost impact estimates
   - Terraform plan output

6. Merge pull request after review

7. Deployment workflow triggers automatically

8. Approve deployment in Actions tab when prompted

**Direct Push to Main:**
```bash
git checkout main
git add terraform/
git commit -m "Deploy infrastructure updates"
git push origin main
```

Note: This bypasses PR validation but still requires manual approval for deployment.

### Destroying Infrastructure

1. Navigate to Actions tab in GitHub repository

2. Select "Terraform Infrastructure Destroy" workflow

3. Click "Run workflow" button

4. Fill in inputs:
   - Confirmation: Type "destroy" exactly
   - Modules: Select target modules or "all"

5. Click "Run workflow"

6. Approve destruction when prompted

7. Monitor progress in Actions tab

8. Verify completion via GitHub issue

## Manual Approval Process

All production deployments and destructions require manual approval:

1. Workflow pauses at environment gate

2. GitHub sends notification to required reviewers

3. Reviewer navigates to workflow run

4. Reviews pending deployment details:
   - Security scan results
   - Cost estimates
   - Terraform plan changes

5. Clicks "Review pending deployments"

6. Selects "production" environment

7. Clicks "Approve and deploy" or "Reject"

8. Workflow continues or stops based on decision

## Security Scanning

I use Checkov to scan Terraform code for security misconfigurations:

**Checked Issues:**
- Unencrypted storage accounts
- Public network access enabled
- Missing network security groups
- Weak TLS versions
- Hardcoded secrets
- Missing RBAC configurations

**Scan Scope:**
- All Terraform modules except OIDC
- Runs before deployment and on PRs
- Blocks deployment if critical issues found

## Cost Estimation

Infracost analyzes Terraform code and provides cost estimates:

**Estimated Resources:**
- Virtual machines and node pools
- Cosmos DB throughput and storage
- Network bandwidth and egress
- Storage accounts
- Container registries

**Cost Visibility:**
- Monthly cost estimates per module
- Cost diff for infrastructure changes
- Breakdown by resource type
- Historical cost tracking via artifacts

## Monitoring and Audit

**GitHub Issues:**
- All deployments create tracking issues
- Success and failure both documented
- Issues include workflow run links
- Searchable via labels

**Workflow Logs:**
- Detailed logs for each step
- Retained for 90 days
- Downloadable for offline review
- Includes Terraform output

**Artifacts:**
- Infracost JSON files (7 day retention)
- Can be downloaded from workflow runs
- Used for cost trend analysis

## Troubleshooting

### Deployment Fails at Security Scan

**Issue:** Checkov finds security violations

**Solution:**
1. Review Checkov output in workflow logs
2. Fix identified security issues in Terraform code
3. Commit fixes and re-run pipeline

### Deployment Fails at Terraform Plan

**Issue:** Terraform validation or plan errors

**Solution:**
1. Check error message in workflow logs
2. Common causes:
   - Missing dependencies
   - Invalid variable values
   - Resource already exists
   - Quota limits exceeded
3. Fix code and retry

### OIDC Authentication Fails

**Issue:** Azure login step fails

**Solution:**
1. Verify secrets are correctly configured
2. Check service principal permissions
3. Ensure federated credential subject matches:
```
   repo:AkingbadeOmosebi/3-Tier-MERN-App:ref:refs/heads/main
```

### State Lock Conflicts

**Issue:** "Error acquiring the state lock"

**Solution:**
1. Check if another workflow is running
2. If stuck, manually break lock:
```bash
terraform force-unlock <lock-id>
```

### Cost Estimation Fails

**Issue:** Infracost step errors

**Solution:**
1. Verify INFRACOST_API_KEY is valid
2. Check API quota at dashboard.infracost.io
3. Retry workflow after verification

## Workflow Exclusions

The following are intentionally excluded from automated workflows:

**OIDC Module:**
- Deployed once manually with local state
- Contains sensitive service principal configuration
- Excluded via path filter: `!terraform/oidc/**`

**Bootstrap Module:**
- Creates Terraform state backend
- Run once locally before pipeline setup
- Not managed by GitHub Actions

## Timeouts

Each job has defined timeouts to prevent hung workflows:

| Job | Timeout | Reason |
|-----|---------|--------|
| Security Scan | 10 minutes | Checkov analysis is fast |
| Cost Estimation | 15 minutes | API calls can be slow |
| Validation | 20 minutes | Multiple plan operations |
| Deployment | 60 minutes | AKS creation takes 15+ minutes |
| Destruction | 90 minutes | Cleanup can be slow |
| Notification | 5 minutes | Simple issue creation |

## Best Practices

**Code Changes:**
- Always create PR for infrastructure changes
- Review security scan results before merge
- Verify cost impact aligns with expectations
- Get peer review for complex changes

**Deployments:**
- Deploy during low-traffic windows
- Monitor Azure portal during deployment
- Keep Terraform state consistent
- Never modify resources manually via portal

**State Management:**
- Never commit local state files
- Always use remote backend
- Verify state lock is released after runs
- Backup state file periodically

**Security:**
- Rotate OIDC credentials annually
- Review Checkov failures seriously
- Never commit secrets to repository
- Use GitHub Secrets for sensitive values

## Pipeline Metrics

**Average Duration:**
- Full deployment: 45-60 minutes
- PR validation: 15-20 minutes
- Destruction: 60-90 minutes

**Success Rate Target:**
- Deployment: >95%
- Security scan: 100% (must pass)
- Cost estimation: >99%

## Contributing

When updating workflows:

1. Test changes in feature branch
2. Verify workflow syntax with GitHub Actions validator
3. Document changes in this README
4. Update timeout values if needed
5. Test manual approval process

## Author

Infrastructure as Code and CI/CD pipeline implemented by Aking Omosebi