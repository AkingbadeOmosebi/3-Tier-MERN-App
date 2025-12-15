# 3-Tier MERN Application - DevSecOps Implementation

[![Build Status](https://github.com/AkingbadeOmosebi/3-Tier-MERN-App/actions/workflows/devsecops-pipeline.yml/badge.svg)](https://github.com/AkingbadeOmosebi/3-Tier-MERN-App/actions/workflows/devsecops-pipeline.yml)

## Overview

This repository demonstrates a production-grade DevSecOps pipeline for a MERN stack application deployed to Azure Kubernetes Service. The implementation follows security best practices with multiple scanning layers, automated versioning, and supply chain security controls.

## Security Pipeline

The CI/CD pipeline implements defense-in-depth with eight security controls:

| Control | Tool | Configuration | Blocking |
|---------|------|---------------|----------|
| Secret Detection | GitLeaks | Git history scan | Yes |
| Dependency Scanning | OWASP Dependency-Check | CVSS 7+ threshold | No (reporting) |
| Static Analysis | SonarCloud | Quality gate enforcement | Yes |
| Dockerfile Linting | Hadolint | Best practices validation | Yes |
| Container Scanning | Trivy | CVE detection (HIGH/CRITICAL) | No (reporting) |
| SBOM Generation | Syft | CycloneDX format | N/A |
| Image Signing | Cosign | Keyless signing (OIDC) | N/A |
| Authentication | Azure OIDC | Passwordless deployment | N/A |

**Rationale for non-blocking scans:** OWASP and Trivy report findings without blocking to demonstrate detection capabilities while allowing continuous delivery. In production, these would be configured based on risk tolerance and vulnerability remediation SLAs.

## Infrastructure

**Cloud Platform:** Microsoft Azure  
**Infrastructure as Code:** Terraform  
**Container Registry:** Azure Container Registry  
**Compute:** Azure Kubernetes Service (planned)  
**Authentication:** OIDC (OpenID Connect) - no stored credentials

### Terraform Modules
```
terraform/
├── oidc/     # Azure AD federated identity for GitHub Actions
├── acr/      # Container registry with role-based access
└── aks/      # Kubernetes cluster configuration (WIP)
```

## CI/CD Architecture
```
┌─────────────────┐
│  Code Push      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Security Scans  │ GitLeaks, OWASP, SonarCloud
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Versioning      │ Semantic Release (Conventional Commits)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Build & Scan    │ Docker build, Hadolint, Trivy, SBOM generation
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Push to ACR     │ OIDC authentication, Cosign signing
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Notification    │ GitHub Issues (audit trail)
└─────────────────┘
```

## Supply Chain Security

**SBOM (Software Bill of Materials):**
- Generated using Anchore Syft
- Format: CycloneDX JSON (OWASP standard)
- Available as build artifacts for vulnerability tracking

**Image Signing:**
- Keyless signing via Cosign and Sigstore
- Signatures verifiable before Kubernetes deployment
- Mitigates container registry compromise attacks

## Version Management

Automated semantic versioning based on Conventional Commits:
- `feat:` → Minor version bump
- `fix:` → Patch version bump  
- `BREAKING CHANGE:` → Major version bump

See [CHANGELOG.md](./CHANGELOG.md) for release history.

## Repository Structure
```
.
├── .github/workflows/
│   └── devsecops-pipeline.yml
├── terraform/
│   ├── oidc/
│   ├── acr/
│   └── aks/
├── MERN-APP/
│   ├── backend/
│   └── frontend/
├── .releaserc.json
└── sonar-project.properties
```

## Security Considerations

**Authentication:** OIDC federation eliminates stored credentials. GitHub Actions authenticates to Azure using short-lived tokens validated against workflow identity.

**Vulnerability Management:** Security scan findings are tracked via GitHub Security tab (SARIF format). Non-blocking scans allow demonstration of detection without preventing deployment.

**Compliance:** SBOM generation supports Executive Order 14028 requirements for federal software supply chain security.

## Technical Stack

**Application:** MongoDB, Express.js, React, Node.js  
**Containerization:** Docker with multi-stage builds  
**Registry:** Azure Container Registry  
**Orchestration:** Azure Kubernetes Service (deployment pending)  
**CI/CD:** GitHub Actions  
**Security:** GitLeaks, OWASP Dependency-Check, SonarCloud, Trivy, Cosign

---

**Author:** Aking Omosebi  
**Role:** Cloud Platform Engineer  
**Focus:** DevSecOps, Infrastructure Automation, Container Security