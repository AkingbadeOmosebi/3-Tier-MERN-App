# Complete Kubernetes Deployment Implementation Guide

**Project:** Production-Grade 3-Tier MERN Application on Azure Kubernetes Service  
**Author:** Akingbade Omosebi  
**Implementation Period:** December 2025  
**Architecture:** Cloud-Native, GitOps, Full Observability

---

## Executive Summary

This document chronicles the complete implementation journey of deploying a production-ready 3-tier MERN application on Azure Kubernetes Service, evolving from basic pod deployments to a sophisticated platform featuring automated certificate management, GitOps-based continuous deployment, and comprehensive observability.

What started as a straightforward container orchestration exercise became an intensive deep-dive into cloud-native patterns, where I encountered real-world challenges around networking, security, automation, and monitoring. Each obstacle revealed gaps in my understanding and pushed me to think like a production platform engineer rather than someone following tutorials.

### What I Built

**Core Infrastructure:**
- 6-node Azure Kubernetes Service cluster (3 system, 3 user nodes)
- Azure Cosmos DB with MongoDB API for data persistence
- Azure Container Registry for image management
- Virtual Network with NSG-protected subnets

**Application Layer:**
- 3 backend replicas (Node.js/Express)
- 3 frontend replicas (React/nginx)
- LoadBalancer → Ingress Controller evolution
- Health checks and resource limits

**Advanced Platform Features:**
- nginx Ingress Controller with host-based routing
- Automatic TLS certificate management via cert-manager and Let's Encrypt
- ArgoCD GitOps platform with auto-sync and self-heal
- Full monitoring stack (Prometheus + Grafana)
- Custom alerting rules for application and cluster health
- ServiceMonitors for metrics collection

**Security and Best Practices:**
- Kubernetes Secrets for credential management
- HTTPS encryption with automatic renewal
- Namespace isolation
- Resource quotas and limits
- Network Security Group rules

**Access Points:**
- Frontend Application: https://mern.ak-cloudtechdigital-az.info
- ArgoCD GitOps UI: https://argocd.ak-cloudtechdigital-az.info
- Grafana Monitoring: https://grafana.ak-cloudtechdigital-az.info

All infrastructure is defined as code, version-controlled in Git, and deployed declaratively through Terraform and ArgoCD.

---

## Table of Contents

1. [Foundation Phase: Basic Kubernetes Deployment](#foundation-phase-basic-kubernetes-deployment)
2. [Networking Evolution: LoadBalancer to Ingress](#networking-evolution-loadbalancer-to-ingress)
3. [Certificate Management: Implementing TLS](#certificate-management-implementing-tls)
4. [GitOps Implementation: ArgoCD Deployment](#gitops-implementation-argocd-deployment)
5. [Observability: Monitoring and Alerting](#observability-monitoring-and-alerting)
6. [Critical Issues and Resolutions](#critical-issues-and-resolutions)
7. [Architecture Decisions](#architecture-decisions)
8. [Lessons Learned](#lessons-learned)
9. [Production Readiness Assessment](#production-readiness-assessment)

---

## Foundation Phase: Basic Kubernetes Deployment

### Starting Point

I began with a containerized MERN application that ran successfully in Docker Compose locally. The challenge was translating this simple local setup into a production-grade Kubernetes deployment on Azure.

### Initial Manifest Structure

I created six core Kubernetes manifests, following a logical dependency order:

**00-namespace.yaml** - Application isolation  
**01-secret.yaml** - Cosmos DB credentials  
**02-backend-deployment.yaml** - API server configuration  
**03-backend-service.yaml** - Internal service discovery  
**04-frontend-deployment.yaml** - React application  
**05-frontend-service.yaml** - Public-facing LoadBalancer

### First Major Struggle: nginx Permission Denied

The very first deployment failed with a cryptic error:

```
nginx: [emerg] bind() to 0.0.0.0:80 failed (13: Permission denied)
```

This was my introduction to container security contexts. I had configured the frontend to run nginx as a non-root user (uid 101) for security, but Linux restricts binding to ports below 1024 to root only.

**My initial solution:** Change nginx to listen on port 8080. This worked but created a cascade of changes across multiple files - Dockerfile, nginx.conf, Kubernetes manifests, health check configurations. Every layer needed updating.

**The reality check:** In production, you often face a choice between security best practices and operational complexity. I chose operational simplicity for the MVP by allowing nginx to run as root, but I documented this decision clearly as ADR-001 (Architecture Decision Record) for future improvement.

This early struggle taught me that container security is not just about adding a `securityContext` block - it requires understanding Linux capabilities, file permissions, and the entire application stack.

### Second Struggle: Cosmos DB Connection Failures

Once pods started running, the backend continuously crashed with:

```
MongoServerError: Command Hello not supported prior to authentication
```

This error was misleading. The real issue was that I was using MongoDB driver options designed for MongoDB 5.0+ (`serverApi` parameter), but Azure Cosmos DB implements the MongoDB 3.6/4.0 wire protocol and doesn't support these newer features.

**The fix required understanding database compatibility:**

```javascript
// Before (didn't work)
const client = new MongoClient(URI, {
  serverApi: ServerApiVersion.v1
});

// After (works with Cosmos DB)
const client = new MongoClient(URI, {
  ssl: true,
  retryWrites: false
});
```

I learned that managed database services often implement API compatibility layers that don't support every feature of the protocol they're emulating. Reading the Cosmos DB documentation revealed specific MongoDB features it doesn't support - a lesson in not assuming full compatibility.

### Third Struggle: Network Security Groups

After fixing the application code, pods were healthy, services were created, the LoadBalancer had a public IP, but the application was still unreachable from the internet.

I worked through systematic debugging:

1. Pod logs showed healthy application startup
2. Service endpoints showed pods properly registered
3. Internal cluster communication worked perfectly
4. External requests timed out

The issue was at the Azure networking layer. The NSG (Network Security Group) attached to the AKS subnet had no rule allowing inbound port 80 from the internet. Kubernetes created the LoadBalancer successfully, but Azure's firewall blocked all traffic to it.

**Resolution:**

```bash
az network nsg rule create \
  --resource-group rg-3tier-mern-prod \
  --nsg-name nsg-aks \
  --name allow-http \
  --priority 100 \
  --source-address-prefixes Internet \
  --destination-port-ranges 80 \
  --access Allow \
  --protocol Tcp
```

This taught me that cloud-native debugging requires thinking in layers: application → pod → service → load balancer → network firewall. Each layer has its own configuration, and all must align for traffic to flow.

### Foundation Phase Outcome

After three days of troubleshooting, I had a working deployment:

- Application accessible via http://50.85.142.123
- All pods healthy with proper health checks
- Data persisting to Cosmos DB
- CI/CD pipeline building and pushing images automatically

But it was far from production-ready. It lacked HTTPS, cost-efficient networking, automated deployments, and observability. These gaps led me to the next phases.

---

## Networking Evolution: LoadBalancer to Ingress

### The Problem with LoadBalancers

My initial architecture used a LoadBalancer service for the frontend. This worked, but I recognized several issues:

**Cost inefficiency:** Each LoadBalancer service provisions a dedicated Azure Load Balancer resource at approximately 20 EUR/month. As the application grew to include multiple services, this cost would multiply.

**Limited routing capabilities:** LoadBalancers provide simple port-based forwarding. I couldn't implement host-based routing, path-based routing, or centralized TLS termination.

**No HTTPS without manual work:** Adding TLS would require manually obtaining certificates, configuring them in the application, and setting up renewal automation.

### Why Ingress Controllers

An Ingress Controller acts as a sophisticated reverse proxy at the cluster edge. It provides:

- Host-based and path-based routing from a single public IP
- Centralized TLS termination
- Integration with cert-manager for automatic certificate management
- Advanced features like rate limiting, authentication, and rewrites

The industry standard is nginx Ingress Controller, which I chose for its maturity, documentation, and Azure compatibility.

### Implementation: Installing nginx Ingress Controller

I used Helm, Kubernetes' package manager, to deploy the Ingress Controller:

```bash
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=//healthz
```

### Windows Git Bash Path Conversion Issue

This installation immediately hit a Windows-specific issue. Git Bash on Windows automatically converts Unix paths to Windows paths, so when I specified:

```
--set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz
```

Git Bash converted `/healthz` to `C:/Program Files/Git/healthz`, which broke Azure Load Balancer health checks. The Azure Load Balancer tried to reach this non-existent Windows path in the Linux container and marked the backend as unhealthy.

**The solution:** Use a double slash (`//healthz`) which Git Bash interprets as an escape sequence, resulting in the correct `/healthz` path in the final configuration.

This was frustrating but taught me an important lesson about cross-platform tooling. The error manifested at the Azure infrastructure layer (health probe failures) but the root cause was in my local shell environment. Debugging required understanding the entire chain: local terminal → Helm → Kubernetes API → Azure Load Balancer.

### Migrating from LoadBalancer to ClusterIP

With the Ingress Controller running, I migrated the frontend service from LoadBalancer to ClusterIP:

**Before:**
```yaml
spec:
  type: LoadBalancer  # Provisions Azure Load Balancer
```

**After:**
```yaml
spec:
  type: ClusterIP  # Internal cluster IP only
```

This change eliminated the standalone public IP while maintaining full functionality. External traffic now flows:

```
Internet → Ingress Controller LB → nginx Ingress pod → frontend ClusterIP service → frontend pods
```

### Creating the Ingress Resource

I created an Ingress resource defining routing rules:

**File:** `07-frontend-ingress.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: frontend-ingress
  namespace: mern-app
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
spec:
  tls:
  - hosts:
    - mern.ak-cloudtechdigital-az.info
    secretName: mern-tls-secret
  rules:
  - host: mern.ak-cloudtechdigital-az.info
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend-service
            port:
              number: 80
```

The Ingress Controller watches for these resources and dynamically reconfigures nginx to implement the routing rules.

### DNS Configuration

I configured DNS A records in Namecheap pointing to the Ingress Controller's public IP (172.199.124.213):

- mern.ak-cloudtechdigital-az.info → 172.199.124.213
- argocd.ak-cloudtechdigital-az.info → 172.199.124.213
- grafana.ak-cloudtechdigital-az.info → 172.199.124.213

All subdomains point to the same IP because the Ingress Controller performs host-based routing by examining HTTP Host headers.

---

## Certificate Management: Implementing TLS

### The Challenge of Manual Certificate Management

Running production applications over HTTP is unacceptable for several reasons:

- Credentials transmitted in plaintext
- No data integrity guarantees
- Browser security warnings
- SEO penalties
- Compliance violations

Manual certificate management is operationally expensive:

- Purchasing certificates annually
- Generating CSRs correctly
- Installing certificates across infrastructure
- Tracking expiration dates
- Coordinating renewal without downtime

### cert-manager: Automated Certificate Lifecycle

cert-manager is a Kubernetes operator that automates certificate acquisition, installation, and renewal. It extends Kubernetes with custom resources for managing certificates declaratively.

**Installation:**

```bash
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.13.3 \
  --set installCRDs=true
```

The `installCRDs=true` flag installs Custom Resource Definitions that teach Kubernetes about certificates:

- **Certificate:** Represents a TLS certificate
- **ClusterIssuer:** Defines a certificate authority
- **CertificateRequest:** Tracks certificate acquisition

### Configuring Let's Encrypt

I created a ClusterIssuer resource to establish communication with Let's Encrypt's ACME (Automated Certificate Management Environment) API:

**File:** `06-clusterissuer.yaml`

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: akingbadeomosebi@gmail.com
    privateKeySecretRef:
      name: letsencrypt-prod-private-key
    solvers:
    - http01:
        ingress:
          class: nginx
```

**How ACME HTTP-01 Challenge Works:**

1. cert-manager requests a certificate for `mern.ak-cloudtechdigital-az.info`
2. Let's Encrypt responds with a challenge token
3. cert-manager creates a temporary Ingress route: `/.well-known/acme-challenge/<TOKEN>`
4. cert-manager places the challenge response at this path
5. Let's Encrypt validates ownership by making an HTTP request to this URL
6. Upon successful validation, Let's Encrypt issues the certificate
7. cert-manager stores the certificate in a Kubernetes Secret
8. The Ingress Controller automatically loads the certificate and enables HTTPS

This entire process happens automatically. I simply annotated my Ingress resource with `cert-manager.io/cluster-issuer: letsencrypt-prod`, and within 60 seconds, I had a valid, trusted TLS certificate.

### HTTPS Traffic Blocked by NSG

After certificate issuance, HTTPS connections still failed. The certificate was valid, nginx was configured correctly, but requests to port 443 timed out.

I checked the NSG rules:

```bash
az network nsg rule list \
  --resource-group rg-3tier-mern-prod \
  --nsg-name nsg-aks \
  --output table
```

Output showed only the HTTP rule:

```
Name        Priority  DestinationPortRanges
----------  --------  ---------------------
allow-http  100       80
```

The NSG allowed port 80 but blocked port 443. I added the missing rule:

```bash
az network nsg rule create \
  --resource-group rg-3tier-mern-prod \
  --nsg-name nsg-aks \
  --name allow-https \
  --priority 110 \
  --source-address-prefixes Internet \
  --destination-port-ranges 443 \
  --access Allow \
  --protocol Tcp \
  --direction Inbound
```

HTTPS immediately started working. This reinforced that cloud networking has multiple layers, and security rules at the infrastructure level override application configurations.

### Browser Cache Confusion

An interesting issue occurred during testing. My primary browser continued showing "Not Secure" warnings despite the certificate being valid. I verified the certificate was correct:

```bash
kubectl get certificate -n mern-app
```

Output showed `READY: True` with a valid Let's Encrypt certificate. Testing in incognito mode and other browsers confirmed HTTPS worked perfectly.

**Root cause:** Browser cache retained invalid certificate state from earlier troubleshooting attempts. A hard refresh (Ctrl+Shift+R) cleared the cached state and showed the valid certificate.

This highlighted that infrastructure changes aren't always immediately visible to clients. Caching at various layers (browser, DNS, CDN) can mask successful deployments.

---

## GitOps Implementation: ArgoCD Deployment

### The Problem with kubectl apply

My initial deployment workflow involved manually running `kubectl apply -f` commands to update the cluster. This approach has serious limitations:

**Lack of audit trail:** No record of who deployed what when  
**No rollback mechanism:** Reverting changes requires manual intervention  
**Drift detection impossible:** Manual changes persist undetected  
**No approval workflow:** Anyone with cluster access can deploy anything  
**Poor scalability:** Doesn't work with multiple engineers or clusters

### GitOps Philosophy

GitOps treats Git as the single source of truth for infrastructure state. The cluster continuously reconciles its actual state with the desired state defined in Git.

**Key principles:**

1. **Declarative:** Entire system state described declaratively
2. **Versioned:** All changes committed to Git with full history
3. **Automatic:** Software agents ensure cluster matches Git
4. **Auditable:** Git log provides complete audit trail

ArgoCD is the leading Kubernetes-native GitOps platform.

### ArgoCD Installation

I installed ArgoCD using Helm:

```bash
helm install argocd argo-cd/argo-cd \
  --namespace argocd \
  --create-namespace
```

This deployed several components:

- **argocd-server:** API server and web UI
- **argocd-application-controller:** Monitors Git and synchronizes cluster state
- **argocd-repo-server:** Clones and caches Git repositories
- **argocd-dex-server:** Authentication provider
- **argocd-redis:** Cache for cluster state

### Exposing ArgoCD UI

I created an Ingress resource to expose the ArgoCD web interface with HTTPS:

**File:** `08-argocd-ingress.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  tls:
  - hosts:
    - argocd.ak-cloudtechdigital-az.info
    secretName: argocd-tls-secret
  rules:
  - host: argocd.ak-cloudtechdigital-az.info
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 443
```

The critical annotation `nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"` tells nginx that the backend service itself serves HTTPS, requiring TLS passthrough.

### Creating the Application Resource

ArgoCD uses Application custom resources to define what to deploy and where. I created a declarative Application manifest:

**File:** `argocd-application.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: mern-app
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  
  source:
    repoURL: https://github.com/AkingbadeOmosebi/3-Tier-MERN-App
    targetRevision: main
    path: k8s-manifests
  
  destination:
    server: https://kubernetes.default.svc
    namespace: mern-app
  
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - Validate=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

**Key configuration decisions:**

**automated.prune: true** - Delete resources removed from Git  
**automated.selfHeal: true** - Revert manual cluster changes back to Git state  
**retry** - Automatically retry failed syncs with exponential backoff

The self-heal feature is particularly powerful. If someone manually scales a deployment or modifies a ConfigMap, ArgoCD detects the drift and automatically reverts the change to match Git within 3 minutes.

### Testing GitOps Workflow

I tested the GitOps workflow end-to-end:

**Test 1: Git-based deployment**
1. Updated replica count in `02-backend-deployment.yaml`
2. Committed and pushed to GitHub
3. Within 3 minutes, ArgoCD detected the change
4. ArgoCD automatically synchronized the new state
5. Kubernetes scaled the deployment to match Git

**Test 2: Self-heal verification**
1. Manually scaled the deployment: `kubectl scale deployment backend --replicas=5`
2. Deployment temporarily scaled to 5 replicas
3. ArgoCD detected drift from Git (which specified 3 replicas)
4. ArgoCD automatically reverted back to 3 replicas within 3 minutes
5. Cluster state matched Git again

This demonstrated that Git is truly the single source of truth. Manual changes are ephemeral.

### ArgoCD Image Updater Challenge

I attempted to configure ArgoCD Image Updater to automatically detect new image tags in Azure Container Registry and update deployments. This proved more complex than expected.

The Helm chart I installed (`argo/argocd-image-updater`) uses a controller-runtime architecture expecting ImageUpdater Custom Resources rather than Application annotations. The documentation showed annotation-based configuration, but the actual implementation required CRs.

After spending 30 minutes troubleshooting, I made a pragmatic decision: skip Image Updater for now and proceed to monitoring implementation. The core GitOps workflow was functioning perfectly - I could trigger deployments by updating image tags in Git, which is sufficient for a portfolio project.

**Lesson learned:** Not every advanced feature needs implementation for MVP. Image Updater is valuable in production where CI/CD pipelines automatically build images, but manual Git-based image updates demonstrate the same GitOps principles with less complexity.

I documented this as a future enhancement: "Phase 2B: Implement ArgoCD Image Updater for automated image version detection and deployment."

---

## Observability: Monitoring and Alerting

### The Observability Problem

Running applications in production without monitoring is like flying blind. You need answers to critical questions:

- Is the application healthy?
- Are users experiencing errors?
- Is resource usage approaching limits?
- Are certificates about to expire?
- Did a deployment cause problems?

Kubernetes provides basic health checks, but comprehensive observability requires dedicated tooling.

### Prometheus and Grafana Stack

The industry-standard Kubernetes monitoring solution is the Prometheus Operator, typically deployed as kube-prometheus-stack. This bundle includes:

**Prometheus:** Time-series database for metrics collection  
**Grafana:** Visualization and dashboarding platform  
**Alertmanager:** Alert routing and notification  
**Node Exporter:** Exposes hardware and OS metrics  
**kube-state-metrics:** Exposes Kubernetes object state  
**Prometheus Operator:** Manages Prometheus instances declaratively

### Installation

I deployed the entire stack with a single Helm command:

```bash
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set grafana.service.type=ClusterIP \
  --set grafana.adminPassword=admin123
```

**Key configuration choices:**

**serviceMonitorSelectorNilUsesHelmValues=false:** Allows Prometheus to discover all ServiceMonitors cluster-wide, not just those created by this Helm release. This enables monitoring of any application.

**grafana.service.type=ClusterIP:** Exposes Grafana internally only. I'll expose it via Ingress with HTTPS rather than creating another LoadBalancer.

**grafana.adminPassword:** Sets a simple initial password. In production, this would integrate with SSO/LDAP.

The installation created approximately 11 pods in the monitoring namespace:

- 1 Prometheus server (stateful, stores metrics)
- 1 Grafana instance
- 1 Alertmanager
- 6 Node Exporters (one per cluster node)
- 1 kube-state-metrics instance
- 1 Prometheus Operator

### Exposing Grafana via Ingress

I created an Ingress resource for Grafana with automatic TLS:

**File:** `09-grafana-ingress.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ingress
  namespace: monitoring
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
spec:
  tls:
  - hosts:
    - grafana.ak-cloudtechdigital-az.info
    secretName: grafana-tls-secret
  rules:
  - host: grafana.ak-cloudtechdigital-az.info
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kube-prometheus-stack-grafana
            port:
              number: 80
```

Within 60 seconds, cert-manager provisioned a valid certificate, and I could access Grafana at https://grafana.ak-cloudtechdigital-az.info.

### ServiceMonitors for Application Metrics

Prometheus uses ServiceMonitor resources to discover which services to scrape for metrics. I created ServiceMonitors for my MERN application:

**File:** `10-servicemonitors.yaml`

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: backend-monitor
  namespace: mern-app
  labels:
    app: backend
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app: backend
  endpoints:
  - port: http
    interval: 30s
    path: /health
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: frontend-monitor
  namespace: mern-app
  labels:
    app: frontend
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app: frontend
  endpoints:
  - port: http
    interval: 30s
    path: /
```

The `release: kube-prometheus-stack` label is critical - it matches the label selector configured in Prometheus, allowing automatic discovery of these ServiceMonitors.

These ServiceMonitors don't expose Prometheus-formatted metrics (my application doesn't have a `/metrics` endpoint), but they enable Prometheus to monitor service availability via health check endpoints.

### Grafana Dashboards

Rather than building dashboards panel-by-panel, I imported pre-built community dashboards from Grafana's dashboard library:

**Dashboard 15760:** Kubernetes Views - Pods  
**Dashboard 15758:** Kubernetes Views - Namespaces  
**Dashboard 15757:** Kubernetes Views - Global

These dashboards provide comprehensive visibility:

- CPU and memory usage per pod
- Network I/O statistics
- Pod restart counts
- Resource requests vs actual usage
- Container logs integration

I can filter dashboards by namespace to focus specifically on the `mern-app` workload, showing real-time metrics for backend and frontend pods.

### Implementing Alert Rules

Metrics are valuable, but alerts enable proactive incident response. I created PrometheusRule resources defining alert conditions:

**File:** `11-prometheus-rules.yaml`

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: mern-portfolio-alerts
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
    role: alert-rules
spec:
  groups:
  - name: mern-application
    interval: 30s
    rules:
    - alert: MERNPodNotReady
      expr: |
        kube_pod_container_status_ready{
          namespace="mern-app"
        } == 0
      for: 2m
      labels:
        severity: critical
        service: mern-portfolio
        team: platform
      annotations:
        summary: "MERN pod not ready"
        description: "One or more MERN containers have been not ready for over 2 minutes."
        runbook_url: "https://github.com/your-org/runbooks/mern-pod-not-ready.md"
    
    - alert: MERNHighCPUUsage
      expr: |
        (
          sum by (pod) (
            rate(container_cpu_usage_seconds_total{
              namespace="mern-app",
              container!="",
              container!="POD"
            }[5m])
          )
          /
          sum by (pod) (
            kube_pod_container_resource_limits_cpu_cores{
              namespace="mern-app"
            }
          )
        ) > 0.8
      for: 5m
      labels:
        severity: warning
        service: mern-portfolio
      annotations:
        summary: "High CPU usage on MERN pod"
        description: "MERN pod CPU usage is above 80% of its configured limit for 5 minutes."
    
    - alert: MERNHighMemoryUsage
      expr: |
        (
          container_memory_working_set_bytes{
            namespace="mern-app",
            container!="",
            container!="POD"
          }
          /
          kube_pod_container_resource_limits_memory_bytes{
            namespace="mern-app"
          }
        ) > 0.8
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "High memory usage on MERN pod"
        description: "MERN pod memory usage exceeds 80% of its memory limit."
```

**Alert design principles:**

**for duration:** Prevents alerting on transient spikes. Alerts only fire if the condition persists for the specified duration.

**Severity levels:** Critical alerts require immediate action, warnings indicate potential issues requiring investigation.

**Runbook URLs:** Annotations include links to runbooks (procedures for resolving the issue). This is a production best practice.

**Label-based queries:** Use Prometheus label selectors to target specific namespaces, making alerts portable across environments.

### Challenges with Alert Rules

My initial alert rule YAML had indentation errors that prevented Kubernetes from accepting it. The error messages were cryptic:

```
Property spec is not allowed.
Property metadata is not allowed.
```

This happened because VS Code didn't recognize PrometheusRule as a valid Kubernetes resource type - my editor didn't have the Prometheus Operator CRD schemas.

**Resolution:** I ignored the editor warnings and applied the manifest anyway. Kubernetes validated it correctly, demonstrating that editor validation can be unreliable for custom resources.

I also tested alert triggering by scaling the backend deployment to zero replicas. The `MERNPodNotReady` alert entered PENDING state immediately, then transitioned to FIRING after 2 minutes. Scaling back to 3 replicas cleared the alert, confirming the alerting pipeline worked correctly.

### Cosmos DB Monitoring Consideration

A complete observability implementation would include database monitoring, but Azure Cosmos DB is a managed service running outside the Kubernetes cluster. Prometheus in-cluster cannot directly scrape Cosmos DB metrics.

**Options considered:**

**Azure Monitor integration:** Export Cosmos DB metrics from Azure Monitor to Prometheus. This requires configuring Azure Monitor workspace and setting up metric exporters - a complex integration beyond tonight's scope.

**Application-level metrics:** Instrument the backend application to expose database query latency, connection pool status, and error rates via a `/metrics` endpoint. This requires code changes.

**Document as future work:** Create placeholder dashboard panels and document Cosmos DB monitoring as a future enhancement.

I chose the third option to maintain momentum. The current monitoring stack provides comprehensive cluster and application visibility. Database-level metrics would enhance this but aren't critical for demonstrating observability capabilities.

---

## Critical Issues and Resolutions

This section documents significant technical challenges encountered during implementation, focusing on the debugging process and resolution strategy rather than just the solution.

### Issue 1: nginx Running as Non-Root User

**Symptom:**
```
nginx: [emerg] bind() to 0.0.0.0:80 failed (13: Permission denied)
```

**Debugging Process:**

I started by examining the pod events:

```bash
kubectl describe pod frontend-xxx -n mern-app
```

Events showed the container starting but immediately failing. I checked the logs:

```bash
kubectl logs frontend-xxx -n mern-app
```

The error was clear - permission denied on port 80. I initially thought this was a Kubernetes-level permission issue and investigated Pod Security Policies.

**Root Cause Analysis:**

The issue was deeper. Linux restricts binding to privileged ports (below 1024) to the root user. My frontend Dockerfile specified:

```dockerfile
USER nginx
```

This directive switches the container process to run as the non-root `nginx` user (uid 101), which cannot bind to port 80.

**Solution Attempts:**

**Attempt 1:** Change nginx to listen on port 8080
- Required updating nginx.conf, Dockerfile EXPOSE, Kubernetes containerPort, Service targetPort
- Created cascading changes across multiple files
- More complex than the problem warranted

**Attempt 2:** Use Linux capabilities
```yaml
securityContext:
  capabilities:
    add:
    - NET_BIND_SERVICE
```
- Would allow non-root user to bind privileged ports
- Required understanding capability system
- More production-appropriate but complex for MVP

**Final Resolution:**

Removed the non-root user requirement for MVP:

```dockerfile
# Removed: USER nginx
# nginx now runs as root
```

**Trade-offs:**

This decision sacrifices some security for operational simplicity. Running as root increases the attack surface if the container is compromised. However, for a portfolio demonstration project with no real user data, this trade-off is acceptable.

I documented this as ADR-001 and noted it as a future security enhancement. In production, I would implement proper non-root containers using capabilities.

**Lesson Learned:**

Security hardening introduces operational complexity. Early-stage projects benefit from working implementations that can be incrementally hardened rather than attempting perfect security from the start.

### Issue 2: Azure NSG Blocking Traffic

**Symptom:**

Pods healthy, services created, LoadBalancer provisioned with public IP, but application unreachable from internet.

**Debugging Process:**

I worked through the networking stack systematically:

**Layer 1 - Pod Health:**
```bash
kubectl get pods -n mern-app
```
All pods Running with 1/1 Ready.

**Layer 2 - Service Endpoints:**
```bash
kubectl get endpoints -n mern-app
```
Endpoints populated with pod IPs, confirming service discovery works.

**Layer 3 - Internal Connectivity:**
```bash
kubectl exec -it backend-xxx -n mern-app -- curl frontend-service
```
Successfully returned HTML, confirming internal cluster networking works.

**Layer 4 - LoadBalancer:**
```bash
kubectl get svc frontend-service -n mern-app
```
EXTERNAL-IP showed a public IP address, confirming Azure provisioned the load balancer.

**Layer 5 - External Connectivity:**
```bash
curl http://<EXTERNAL-IP>
```
Connection timeout, confirming the issue is at the Azure infrastructure layer.

**Root Cause:**

The Azure Network Security Group (NSG) attached to the AKS subnet had no inbound rule allowing port 80 from the internet. NSG is Azure's stateful firewall - it evaluates every packet against configured rules and blocks anything not explicitly allowed.

Default NSG rules only allow traffic from within the virtual network. My Terraform code created the NSG but didn't include application-level port rules (by design - I wanted the cluster to be secure by default).

**Resolution:**

Created NSG rule to allow HTTP traffic:

```bash
az network nsg rule create \
  --resource-group rg-3tier-mern-prod \
  --nsg-name nsg-aks \
  --name allow-http \
  --priority 100 \
  --source-address-prefixes Internet \
  --destination-port-ranges 80 \
  --access Allow \
  --protocol Tcp \
  --direction Inbound
```

Application immediately became accessible.

**Lesson Learned:**

Cloud networking has multiple layers of control: Kubernetes Services, Cloud Load Balancers, Network Firewalls (NSG), Application Firewalls (WAF). Each layer can block traffic independently. Systematic debugging from the pod outward identifies which layer is problematic.

This taught me to verify infrastructure-level networking rules when Kubernetes reports healthy resources but external access fails.

### Issue 3: Windows Git Bash Path Conversion

**Symptom:**

Azure Load Balancer health probes failing for nginx Ingress Controller, marking backend as unhealthy and refusing to forward traffic.

**Debugging Process:**

I checked the Load Balancer health probe configuration in Azure Portal:

```
Health probe path: C:/Program Files/Git/healthz
```

This was clearly wrong - I specified `/healthz` but somehow it became a Windows path.

**Root Cause:**

Windows Git Bash automatically converts Unix-style paths to Windows paths to enable interoperability with Windows tools. When I ran:

```bash
helm install ... --set path=/healthz
```

Git Bash interpreted `/healthz` as an absolute Unix path and converted it to `C:/Program Files/Git/healthz` before passing it to Helm.

**Resolution:**

Use double-slash to bypass path conversion:

```bash
helm install ... --set path=//healthz
```

Git Bash treats `//` as an escape sequence, passing it through as `/` to Helm, which then correctly configures the health probe.

**Lesson Learned:**

Cross-platform tooling introduces subtle issues. Windows developers working with Linux-first tools must understand these quirks. The error manifested at the Azure infrastructure layer (health probe configuration), but the root cause was in the local shell environment.

This reinforced that effective debugging requires understanding the entire toolchain: local terminal → package manager → Kubernetes API → cloud provider.

### Issue 4: Browser Caching Invalid TLS State

**Symptom:**

Certificate successfully provisioned (kubectl shows READY: True), Let's Encrypt validation passed, but browser shows "Not Secure" warning.

**Debugging Process:**

**Verification 1 - Certificate Status:**
```bash
kubectl get certificate -n mern-app
```
Shows READY: True with valid Let's Encrypt certificate.

**Verification 2 - Certificate Details:**
```bash
kubectl describe certificate mern-tls-secret -n mern-app
```
Shows successful issuance from Let's Encrypt R12 authority.

**Verification 3 - Alternative Browser:**
Opened incognito mode - certificate showed as valid with green padlock.

**Verification 4 - Different Browser:**
Tested in Firefox - certificate valid.

**Root Cause:**

Primary browser cached invalid certificate state from earlier troubleshooting. During initial testing, I accessed the site before the certificate was provisioned. The browser cached this "invalid certificate" state and continued displaying the warning even after a valid certificate was installed.

**Resolution:**

Hard refresh: `Ctrl + Shift + R` cleared the cached state and displayed the valid certificate correctly.

**Lesson Learned:**

Infrastructure changes aren't always immediately visible to clients. Caching occurs at multiple layers: browser cache, DNS cache, CDN cache. When validating deployments, use cache-bypass methods (incognito mode, hard refresh, curl) to verify actual state rather than cached state.

### Issue 5: PrometheusRule Label Mismatch

**Symptom:**

PrometheusRule resource created successfully but alerts don't appear in Prometheus UI or Alertmanager.

**Debugging Process:**

**Check 1 - Resource Creation:**
```bash
kubectl get prometheusrule -n monitoring
```
Shows `mern-app-alerts` created successfully.

**Check 2 - Prometheus Configuration:**
```bash
kubectl get prometheus -n monitoring -o yaml | grep -A 5 ruleSelector
```

Output showed Prometheus configured to select rules with label `release: kube-prometheus-stack`.

My PrometheusRule used label `prometheus: kube-prometheus-stack-prometheus` instead.

**Root Cause:**

Prometheus uses label selectors to determine which PrometheusRules to load. The label mismatch meant Prometheus ignored my rules even though they existed in Kubernetes.

**Resolution:**

Updated PrometheusRule labels to match Prometheus selector:

```yaml
metadata:
  labels:
    release: kube-prometheus-stack  # Changed from prometheus: ...
    role: alert-rules
```

Prometheus immediately detected and loaded the rules.

**Lesson Learned:**

Custom Resource Definitions often use label selectors to create loose coupling between resources. Understanding these selectors is critical when working with operators like Prometheus Operator or ArgoCD.

When a CRD resource exists but doesn't produce expected behavior, check label selectors first.

---

## Architecture Decisions

This section documents key architectural decisions made during implementation, following the Architecture Decision Record (ADR) pattern.

### ADR-001: Single Ingress Controller Pattern

**Decision:** Use one nginx Ingress Controller for all external traffic rather than multiple LoadBalancer services.

**Context:**

Initial architecture used LoadBalancer service type for the frontend, which provisions a dedicated Azure Load Balancer resource. As I planned to expose ArgoCD and Grafana, this approach would create three separate load balancers.

**Considered Alternatives:**

1. **Multiple LoadBalancers:** Each service gets its own public IP via dedicated Azure Load Balancer
2. **Single Ingress Controller:** One nginx-based reverse proxy handling all external traffic
3. **Application Gateway Ingress Controller (AGIC):** Azure-native ingress using Application Gateway

**Decision Rationale:**

Chose single Ingress Controller because:

**Cost optimization:** One Azure Load Balancer (~20 EUR/month) vs three (~60 EUR/month)

**Centralized TLS termination:** Single point for certificate management

**Advanced routing:** Host-based routing enables multiple services from one IP

**Operational simplicity:** One component to monitor and troubleshoot

**Industry standard:** nginx Ingress Controller is the de facto standard with extensive documentation

**Consequences:**

**Positive:**
- Reduced infrastructure cost
- Simplified DNS configuration (all domains point to one IP)
- Centralized logging and monitoring for HTTP traffic
- Support for advanced features (rate limiting, auth, rewrites)

**Negative:**
- Single point of failure (mitigated by controller replica scaling)
- Slightly higher latency (additional hop through proxy)
- Requires understanding Ingress resources and nginx configuration

**Status:** Implemented and operational.

---

### ADR-002: Automated Certificate Management via cert-manager

**Decision:** Use cert-manager with Let's Encrypt for automatic TLS certificate acquisition and renewal.

**Context:**

Production applications require HTTPS encryption. Manual certificate management involves purchasing certificates, generating CSRs, installing certificates, and tracking expiration dates.

**Considered Alternatives:**

1. **Manual certificates:** Purchase from commercial CA, manually install and renew
2. **cert-manager + Let's Encrypt:** Automated acquisition and renewal
3. **Azure-managed certificates:** Use Azure Front Door or Application Gateway with managed certificates
4. **Self-signed certificates:** Generate and distribute self-signed certs

**Decision Rationale:**

Chose cert-manager because:

**Automation:** Eliminates manual certificate lifecycle management

**Cost:** Let's Encrypt provides free certificates

**Integration:** Native Kubernetes integration via CRDs

**Industry standard:** cert-manager is the de facto standard for Kubernetes certificate management

**Automatic renewal:** Certificates renew 30 days before expiration with no manual intervention

**Consequences:**

**Positive:**
- Zero cost for certificates
- No manual renewal process
- 90-day certificate lifetime encourages automation
- Full audit trail of certificate requests in Kubernetes events
- Works consistently across any Kubernetes environment

**Negative:**
- Let's Encrypt rate limits (50 certificates per domain per week)
- Requires public internet accessibility for HTTP-01 challenges
- 90-day expiration means renewals happen more frequently than annual commercial certificates
- Trust depends on Let's Encrypt infrastructure availability

**Status:** Implemented with three successful certificate acquisitions (mern, argocd, grafana subdomains).

---

### ADR-003: GitOps with ArgoCD Auto-Sync and Self-Heal

**Decision:** Configure ArgoCD with automatic synchronization and self-heal enabled.

**Context:**

ArgoCD can operate in manual mode (require approval for syncs) or automatic mode (sync changes immediately). Similarly, drift can be detected-only or automatically corrected.

**Considered Alternatives:**

1. **Manual sync only:** Require explicit approval for all changes
2. **Auto-sync without self-heal:** Automatically deploy Git changes but allow manual cluster modifications
3. **Auto-sync with self-heal:** Automatically deploy Git changes and revert manual modifications

**Decision Rationale:**

Chose auto-sync with self-heal because:

**True GitOps:** Git is unambiguously the single source of truth

**Prevents drift:** Manual changes don't accumulate undetected

**Operational efficiency:** No manual intervention needed for routine deployments

**Demonstrates advanced understanding:** Shows mastery of GitOps principles for portfolio purposes

**Consequences:**

**Positive:**
- Git commits automatically deploy to cluster within 3 minutes
- Configuration drift detected and corrected automatically
- Full audit trail in Git log
- Simplified operations (no manual kubectl commands)
- Infrastructure recovers automatically from manual errors

**Negative:**
- Manual debugging changes are immediately reverted
- Requires discipline to always update Git rather than cluster directly
- Emergency fixes must go through Git (adds 3-minute delay)
- Can confuse engineers unfamiliar with GitOps patterns

**Mitigation:** Implemented comprehensive commit messages and documented the auto-sync behavior clearly.

**Status:** Implemented and tested. Self-heal successfully reverted manual deployment scaling.

---

### ADR-004: ArgoCD Write-Back Method Selection

**Decision:** Skip ArgoCD Image Updater for MVP; document as future enhancement.

**Context:**

ArgoCD Image Updater can automatically detect new container images in registries and update deployments. It supports two write-back methods:

- **argocd write-back:** Store image overrides in ArgoCD Application resource
- **git write-back:** Commit image tag changes directly to Git repository

**Considered Alternatives:**

1. **Implement argocd write-back:** Simpler configuration, no GitHub credentials needed
2. **Implement git write-back:** True GitOps with full Git audit trail
3. **Skip Image Updater:** Manual image updates via Git commits

**Decision Rationale:**

Chose to skip Image Updater because:

**Time constraints:** Already invested 30 minutes troubleshooting CR-based vs annotation-based configuration

**Diminishing returns:** Core GitOps functionality works perfectly; Image Updater is enhancement not requirement

**Manual updates acceptable:** For portfolio project, manually updating image tags in Git demonstrates same GitOps workflow

**Focus on monitoring:** Remaining time better spent implementing observability stack

**Consequences:**

**Positive:**
- More time available for monitoring implementation
- Simpler architecture with fewer moving parts
- Manual image updates still follow GitOps patterns
- Can be added later without architectural changes

**Negative:**
- Requires manual Git commits to update image tags
- Doesn't demonstrate full automation from image build to deployment
- No automatic rollback if new image fails health checks

**Future Enhancement:** Documented as "Phase 2B: Implement ArgoCD Image Updater with git write-back method for complete automation."

**Status:** Deferred to future implementation.

---

### ADR-005: Community Grafana Dashboards vs Custom Development

**Decision:** Import pre-built community Grafana dashboards rather than building custom dashboards from scratch.

**Context:**

Grafana dashboards can be built panel-by-panel in the UI or imported from Grafana's dashboard library (grafana.com/grafana/dashboards).

**Considered Alternatives:**

1. **Build custom dashboards:** Create every panel manually with custom queries
2. **Import community dashboards:** Use pre-built dashboards from Grafana library
3. **Hybrid approach:** Import community dashboards and customize with additional panels

**Decision Rationale:**

Chose community dashboards because:

**Time efficiency:** Ready-made dashboards deployable in minutes vs hours of custom development

**Best practices:** Community dashboards reflect battle-tested metrics and layouts

**Comprehensive coverage:** Pre-built dashboards include metrics I might not have considered

**Professional appearance:** Community dashboards are polished and well-designed

**Industry standard:** Using popular dashboards (15760, 15758, 15757) demonstrates knowledge of ecosystem

**Consequences:**

**Positive:**
- Instant professional dashboards showing cluster health
- Comprehensive metric coverage
- Regular updates from dashboard maintainers
- Can export and customize later
- Demonstrates pragmatic approach to tooling

**Negative:**
- Less opportunity to demonstrate PromQL expertise
- Dashboards may include irrelevant panels
- Generic appearance without application-specific branding
- Missed opportunity to showcase custom visualization skills

**Mitigation:** Can add custom panels for MERN-specific metrics as future enhancement.

**Status:** Implemented with dashboards 15760, 15758, and 15757.

---

## Lessons Learned

### Technical Lessons

**1. Cloud Networking Has Multiple Layers**

The most valuable lesson was understanding that cloud networking operates in distinct layers, each with independent configuration and potential failure points:

- Application layer (container port bindings)
- Kubernetes layer (Services, Ingress resources)
- Cloud provider layer (Load Balancers)
- Network layer (NSG rules, firewall policies)

Debugging requires systematic verification from the application outward. When external access fails despite healthy pods, the issue is almost always at the infrastructure layer.

**2. Security Best Practices vs Operational Complexity**

Running containers as non-root users, implementing Pod Security Standards, and enforcing network policies are security best practices. However, each adds operational complexity.

For MVP and portfolio projects, I learned to make conscious trade-offs: implement a working system first, then incrementally harden security. Document security gaps as known limitations rather than attempting perfect security from the start.

**3. Certificate Automation Eliminates Entire Classes of Problems**

Manual certificate management introduces:
- Surprise expiration outages
- Complex renewal procedures
- Coordination across teams
- Risk of misconfiguration

cert-manager eliminates all these issues. The 10 minutes invested in cert-manager setup saves hours of manual work and prevents production outages.

**4. GitOps Requires Discipline But Provides Immense Value**

The GitOps pattern (Git as single source of truth, automated reconciliation) requires behavioral changes:
- No more manual kubectl apply commands
- All changes must go through Git
- Accept 3-minute sync delay for deployments

Initially frustrating, but the benefits are substantial:
- Complete audit trail
- Automated rollback
- Drift detection
- Multi-cluster consistency

**5. Cross-Platform Tooling Has Hidden Gotchas**

Windows Git Bash path conversion (`/healthz` → `C:/Program Files/Git/healthz`) taught me that cross-platform development introduces subtle issues. Errors manifest far from their root cause (Azure Load Balancer health probe failures caused by local shell environment).

The lesson: when debugging unexpected behavior, consider the entire toolchain including local environment.

### Process Lessons

**1. Systematic Debugging Beats Trial and Error**

When facing unfamiliar errors, I learned to:
- Verify each layer independently
- Work from known-good to suspected-bad
- Document findings at each step
- Avoid jumping to solutions

The NSG blocking traffic was found through systematic layer verification, not through guessing.

**2. Documentation Is Part of Implementation**

I initially viewed documentation as a post-implementation task. I learned that documenting decisions, trade-offs, and known issues during implementation:
- Clarifies thinking
- Captures context that's lost later
- Makes troubleshooting easier
- Demonstrates professional engineering

Architecture Decision Records (ADRs) formalize this practice.

**3. Time-Boxing Investigation Prevents Rabbit Holes**

The ArgoCD Image Updater issue consumed 30 minutes. I learned to time-box investigation: after N minutes without progress, reassess priorities. Is solving this issue critical for the current goal?

Deferring Image Updater allowed me to complete monitoring implementation. Image Updater can be added later without disrupting the architecture.

**4. Community Resources Accelerate Learning**

Grafana community dashboards, Helm charts, and GitHub issues provided ready-made solutions and troubleshooting guidance. I learned to search for existing solutions before building custom ones.

**5. Realistic Portfolio Demonstrations**

Perfect implementations aren't necessary for portfolio projects. Demonstrating:
- Working systems
- Understanding of trade-offs
- Documentation of known limitations
- Path to production-readiness

... is more valuable than attempting perfect production deployments in unrealistic timelines.

### Skills Developed

**Technical Skills:**
- Kubernetes Ingress Controllers and routing
- Certificate management with cert-manager
- GitOps patterns with ArgoCD
- Prometheus metrics and alerting
- Grafana dashboard configuration
- Azure networking (NSG, Load Balancers)
- Helm chart deployment and configuration
- PromQL query language
- Custom Resource Definitions

**Operational Skills:**
- Systematic debugging methodology
- Cross-layer troubleshooting (application → infrastructure)
- Log analysis and event correlation
- Cloud resource monitoring

**Architectural Skills:**
- Making conscious trade-offs (security vs complexity)
- Documenting decisions with rationale
- Identifying critical vs nice-to-have features
- Planning incremental improvements

---

## Production Readiness Assessment

This section evaluates the current implementation against production requirements and identifies gaps requiring remediation.

### Current Capabilities

**Availability:**
- ✅ 3 replicas for both frontend and backend (tolerates node failures)
- ✅ Health checks enable automatic pod recovery
- ✅ Rolling update strategy ensures zero-downtime deployments
- ✅ Multiple availability zones supported by AKS node pools

**Security:**
- ✅ HTTPS encryption with valid certificates
- ✅ Automatic certificate renewal
- ✅ Kubernetes Secrets for credentials
- ✅ Namespace isolation
- ✅ NSG firewall rules limiting inbound traffic
- ⚠️ Containers run as root (documented limitation)
- ❌ No network policies restricting pod-to-pod traffic
- ❌ No Pod Security Standards enforcement
- ❌ No WAF protecting against application attacks
- ❌ Secrets stored in etcd (should use Azure Key Vault)

**Observability:**
- ✅ Comprehensive metrics collection (Prometheus)
- ✅ Professional dashboards (Grafana)
- ✅ Alert rules for critical conditions
- ✅ ServiceMonitors for application health
- ⚠️ No application performance monitoring (APM)
- ⚠️ No distributed tracing
- ❌ No log aggregation (should implement Loki or ELK)
- ❌ No alert routing (Alertmanager configured but no notification channels)

**Automation:**
- ✅ GitOps deployment via ArgoCD
- ✅ Automatic sync from Git
- ✅ Self-heal prevents drift
- ✅ Terraform for infrastructure provisioning
- ✅ GitHub Actions CI/CD for image builds
- ⚠️ Manual image version updates (Image Updater not implemented)
- ❌ No automated rollback on health check failures

**Resilience:**
- ✅ Stateless application pods (horizontally scalable)
- ✅ Managed database (Cosmos DB handles replication)
- ✅ Resource limits prevent resource exhaustion
- ⚠️ No pod disruption budgets
- ❌ No autoscaling (HPA/VPA not configured)
- ❌ No disaster recovery procedures documented

**Cost Optimization:**
- ✅ Single Ingress Controller vs multiple LoadBalancers
- ✅ Right-sized resource requests and limits
- ⚠️ Fixed node count (should implement cluster autoscaler)
- ❌ No cost monitoring or budget alerts

### Production Readiness Score: 65%

**Ready for production:**
- Small-scale applications
- Internal tools
- Development/staging environments

**Not ready for:**
- High-traffic public applications
- Applications handling sensitive data
- Regulated environments (HIPAA, PCI-DSS)
- Multi-tenant scenarios

### Critical Path to Production

**Phase 1: Security Hardening (1-2 weeks)**

1. Implement network policies restricting pod communication
2. Enable Pod Security Standards
3. Integrate Azure Key Vault for secrets management
4. Run containers as non-root users with capabilities
5. Implement WAF (ModSecurity on nginx Ingress)
6. Configure security scanning in CI/CD admission control

**Phase 2: Enhanced Observability (1 week)**

1. Deploy Loki for log aggregation
2. Implement distributed tracing (Jaeger or Tempo)
3. Configure Alertmanager notification channels (PagerDuty, Slack)
4. Add custom application metrics
5. Create runbooks for alert responses
6. Implement synthetic monitoring for critical paths

**Phase 3: Resilience and Scaling (1 week)**

1. Configure Horizontal Pod Autoscaler based on CPU/memory
2. Implement Pod Disruption Budgets
3. Enable cluster autoscaler
4. Document disaster recovery procedures
5. Test backup and restore procedures
6. Implement chaos engineering tests

**Phase 4: Operational Excellence (ongoing)**

1. Establish SLOs (Service Level Objectives)
2. Implement SLI (Service Level Indicator) dashboards
3. Configure cost monitoring and budget alerts
4. Establish change management processes
5. Create operational runbooks
6. Implement progressive delivery (canary deployments)

**Estimated total effort:** 4-6 weeks of focused engineering work.

---

## Conclusion

This implementation journey transformed a basic containerized application into a sophisticated cloud-native platform. I progressed from struggling with nginx permissions to implementing enterprise-grade patterns like GitOps and comprehensive observability.

### Key Achievements

**Technical:**
- Deployed production-grade Kubernetes architecture on Azure
- Implemented automated certificate management with zero manual intervention
- Established GitOps workflow ensuring Git is single source of truth
- Built comprehensive monitoring and alerting infrastructure
- Created fully declarative, version-controlled infrastructure

**Personal:**
- Developed systematic debugging methodology
- Learned to make conscious architectural trade-offs
- Understood cloud networking in depth (application → infrastructure layers)
- Experienced real-world challenges absent from tutorials
- Built professional documentation practices

**Professional:**
- Created portfolio-worthy project demonstrating advanced Kubernetes skills
- Documented decision-making process and trade-offs
- Demonstrated production thinking (not just getting it working)
- Showed ability to learn complex technologies quickly
- Proved capability to troubleshoot unfamiliar systems

### What Makes This Implementation Valuable

This isn't a tutorial-following exercise. The value comes from:

**Real problems solved:** nginx permissions, NSG blocking, path conversion, alert configuration
**Production patterns implemented:** GitOps, automated certificates, comprehensive monitoring
**Conscious trade-offs:** Security vs complexity, custom vs community dashboards
**Complete documentation:** Every decision explained with context and rationale
**Gap identification:** Honest assessment of what's missing for true production readiness

### Next Steps

**Immediate:**
1. Implement ArgoCD Image Updater for complete automation
2. Add custom Grafana panels for MERN-specific metrics
3. Configure Alertmanager notification channels

**Short-term (1-2 months):**
1. Security hardening (network policies, Pod Security Standards)
2. Log aggregation (Loki)
3. Cost monitoring dashboard

**Long-term (3-6 months):**
1. Multi-cluster ArgoCD
2. Progressive delivery with Argo Rollouts
3. Service mesh evaluation (Istio/Linkerd)

### Final Reflection

The most valuable lesson from this project wasn't any specific technology - it was learning to think like a platform engineer. Platform engineering isn't about memorizing kubectl commands or knowing every Kubernetes feature. It's about:

- Understanding the full stack (application to infrastructure)
- Systematic troubleshooting across layers
- Making conscious trade-offs with full context
- Documenting decisions for future maintainers
- Recognizing when to defer features vs implement now
- Building incrementally with production in mind

This project demonstrates that I can take a simple application and transform it into a production-ready platform while understanding every decision made along the way.

---

**Project Repository:** https://github.com/AkingbadeOmosebi/3-Tier-MERN-App  
**Live Application:** https://mern.ak-cloudtechdigital-az.info  
**ArgoCD Dashboard:** https://argocd.ak-cloudtechdigital-az.info  
**Grafana Monitoring:** https://grafana.ak-cloudtechdigital-az.info

**Author:** Akingbade Omosebi  
**Role:** Cloud Platform Engineer  
**Implementation Period:** December 2025  
**Document Version:** 1.0