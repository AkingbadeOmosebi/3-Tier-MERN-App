# Kubernetes Manifests Technical Reference

**Author:** Akingbade Omosebi  
**Project:** 3-Tier MERN Application on Azure Kubernetes Service  
**Date:** December 2025

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture Decision Records](#architecture-decision-records)
3. [Manifest Breakdown](#manifest-breakdown)
4. [Common Issues and Resolutions](#common-issues-and-resolutions)
5. [Security Considerations](#security-considerations)

---

## Overview

This document provides a comprehensive technical reference for the Kubernetes manifests used to deploy a production-grade 3-tier MERN application on Azure Kubernetes Service. The deployment architecture follows cloud-native best practices including namespace isolation, secrets management, health checks, and high availability configurations.

The application stack consists of:
- Frontend: React SPA served via nginx
- Backend: Node.js Express API
- Database: Azure Cosmos DB (MongoDB API)

All components run in a dedicated Kubernetes namespace with proper resource limits, readiness/liveness probes, and service discovery configurations.

---

## Architecture Decision Records

### ADR-001: Namespace Isolation

**Decision:** Deploy all application components in a dedicated `mern-app` namespace rather than using the default namespace.

**Rationale:**
- Logical isolation from system components and other applications
- Easier RBAC policy management
- Simplified resource quotas and network policies
- Clean separation for monitoring and logging

**Implementation:** All manifests specify `namespace: mern-app` in metadata.

---

### ADR-002: Secrets Management

**Decision:** Use Kubernetes native Secrets with base64 encoding for Cosmos DB connection strings.

**Rationale:**
- Kubernetes Secrets are encrypted at rest in etcd
- Native integration with pods via environment variables
- No external secret management system required for MVP
- Azure AD RBAC controls access to secrets

**Future Consideration:** Migrate to Azure Key Vault integration via CSI driver for enhanced security and secret rotation capabilities.

---

### ADR-003: Service Types

**Decision:**
- Backend: ClusterIP (internal only)
- Frontend: LoadBalancer (public access)

**Rationale:**
- Backend should never be directly accessible from internet
- Frontend LoadBalancer provides Azure-managed public IP with health checks
- Simpler than Ingress for initial deployment
- Can migrate to Ingress later without rebuilding images

**Trade-off:** Each LoadBalancer costs approximately $20/month. Ingress would reduce this to a single public IP.

---

### ADR-004: Replica Count

**Decision:** Run 3 replicas for both frontend and backend.

**Rationale:**
- High availability across multiple AKS nodes
- Zero-downtime deployments during updates
- Tolerates single node failure
- Load distribution for better performance

**Resource Impact:** 6 total pods (3 frontend + 3 backend) consuming approximately 2.25 GB RAM and 1.5 CPU cores total.

---

### ADR-005: Health Check Strategy

**Decision:** Implement both liveness and readiness probes with different purposes.

**Rationale:**
- Liveness probes detect hung processes and trigger restarts
- Readiness probes prevent traffic to pods during startup or overload
- Separate concerns allow better failure handling

**Configuration:**
- Backend: `/health` endpoint returning JSON with uptime
- Frontend: nginx root `/` endpoint
- Initial delays account for application startup time

---

## Manifest Breakdown

### 00-namespace.yaml

**Purpose:** Creates isolated namespace for application components.

**Key Configuration:**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: mern-app
  labels:
    name: mern-app
    environment: production
```

**Why It Matters:** Namespaces provide logical isolation, simplified resource management, and clean separation for RBAC policies. All subsequent manifests reference this namespace.

---

### 01-secret.yaml

**Purpose:** Securely stores Cosmos DB connection credentials.

**Key Configuration:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cosmos-secret
  namespace: mern-app
type: Opaque
data:
  mongodb-uri: <base64-encoded-connection-string>
  db-name: <base64-encoded-database-name>
```

**Security Notes:**
- Data is base64 encoded (not encrypted in manifest, but encrypted at rest in etcd)
- Never commit actual secrets to Git
- Use different secrets for different environments
- Secrets are mounted as environment variables in pods

**Access Pattern:**
```yaml
env:
- name: MONGODB_URI
  valueFrom:
    secretKeyRef:
      name: cosmos-secret
      key: mongodb-uri
```

Kubernetes automatically decodes base64 when injecting into pods.

---

### 02-backend-deployment.yaml

**Purpose:** Defines how backend API pods should run, including replicas, resources, and health checks.

**Key Configuration Sections:**

#### Replica Management
```yaml
spec:
  replicas: 3
  selector:
    matchLabels:
      app: backend
```

The selector matches pods with label `app: backend`. Kubernetes maintains exactly 3 pods matching this label.

#### Container Specification
```yaml
containers:
- name: backend
  image: acr3tiermernappao.azurecr.io/backend:v1.10.0
  imagePullPolicy: Always
  ports:
  - containerPort: 5050
    name: http
```

Key decisions:
- `imagePullPolicy: Always` ensures latest image is pulled on each deployment
- Named port `http` for service discovery
- Specific version tag for reproducibility

#### Environment Variables
```yaml
env:
- name: MONGODB_URI
  valueFrom:
    secretKeyRef:
      name: cosmos-secret
      key: mongodb-uri
- name: DB_NAME
  valueFrom:
    secretKeyRef:
      name: cosmos-secret
      key: db-name
- name: PORT
  value: "5050"
- name: NODE_ENV
  value: "production"
```

Pattern used: Sensitive data from Secrets, configuration from direct values. This separation allows changing config without rebuilding images.

#### Resource Limits
```yaml
resources:
  requests:
    cpu: 250m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

**Requests vs Limits:**
- **Requests:** Guaranteed minimum resources for pod scheduling
- **Limits:** Maximum resources pod can consume before throttling/OOM

**Why These Values:**
- Backend is CPU-bound during API processing
- 256Mi base memory for Node.js runtime
- 512Mi limit allows burst processing
- 250m CPU request ensures responsive API

#### Health Checks
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 5050
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 3
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /health
    port: 5050
  initialDelaySeconds: 10
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 3
```

**Probe Differentiation:**
- **Liveness:** Checks if container is alive. Failure = restart container
- **Readiness:** Checks if container is ready for traffic. Failure = remove from service endpoints

**Timing Strategy:**
- Liveness starts after 30s (allows Node.js app to initialize)
- Readiness starts after 10s (faster to begin accepting traffic)
- More frequent readiness checks (5s vs 10s) for quicker traffic routing decisions

---

### 03-backend-service.yaml

**Purpose:** Provides stable internal endpoint for backend pods with automatic load balancing.

**Key Configuration:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: backend-service
  namespace: mern-app
spec:
  type: ClusterIP
  selector:
    app: backend
  ports:
  - name: http
    port: 5050
    targetPort: 5050
    protocol: TCP
```

**How It Works:**
1. Service automatically discovers all pods with label `app: backend`
2. Creates internal DNS entry: `backend-service.mern-app.svc.cluster.local`
3. Load balances requests across all healthy backend pods
4. Automatically removes unhealthy pods from rotation based on readiness probes

**DNS Resolution:**
- Full FQDN: `backend-service.mern-app.svc.cluster.local:5050`
- Short form (within same namespace): `backend-service:5050`
- Frontend nginx uses full FQDN for explicit clarity

**Type: ClusterIP**
- Only accessible within cluster
- No external IP assigned
- Cannot be reached from internet
- Backend remains protected behind frontend proxy

---

### 04-frontend-deployment.yaml

**Purpose:** Defines how frontend nginx pods serve the React SPA and proxy API requests.

**Key Configuration Sections:**

#### Container Specification
```yaml
containers:
- name: frontend
  image: acr3tiermernappao.azurecr.io/frontend:v1.10.0
  imagePullPolicy: Always
  ports:
  - containerPort: 80
    name: http
```

**Why Port 80:**
- nginx default port
- No privilege issues (running as root in simplified config)
- Standard HTTP port for LoadBalancer mapping

#### Resource Allocation
```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 256Mi
```

**Lower than Backend Because:**
- nginx serves static files (low CPU)
- No database connections or heavy processing
- React app is pre-built JavaScript

#### Health Checks
```yaml
livenessProbe:
  httpGet:
    path: /
    port: 80
  initialDelaySeconds: 10
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /
    port: 80
  initialDelaySeconds: 5
  periodSeconds: 5
```

**Simpler than Backend:**
- nginx starts faster than Node.js
- Shorter initial delays
- Check root path (static file serving)

---

### 05-frontend-service.yaml

**Purpose:** Exposes frontend to internet via Azure LoadBalancer.

**Key Configuration:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
  namespace: mern-app
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path: /
spec:
  type: LoadBalancer
  selector:
    app: frontend
  ports:
  - name: http
    port: 80
    targetPort: 80
    protocol: TCP
  sessionAffinity: ClientIP
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: 10800
```

**Type: LoadBalancer**
- Azure automatically provisions Azure Load Balancer
- Public IP address assigned
- Health probes configured automatically
- Managed by Azure cloud controller

**Session Affinity:**
```yaml
sessionAffinity: ClientIP
timeoutSeconds: 10800
```

**Purpose:** Routes requests from same client IP to same pod for 3 hours.

**Why:**
- Maintains WebSocket connections if added later
- Improves cache hit rates in nginx
- Better user experience during pod scaling

**Azure Health Probe Annotation:**
```yaml
service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path: /
```

Tells Azure LoadBalancer to use root path for health checks instead of random TCP probes.

---

## Common Issues and Resolutions

### Issue 1: OIDC Subject Claim Mismatch

**Error:**
```
Error: AADSTS700213: No matching federated identity record found for presented 
assertion subject 'repo:AkingbadeOmosebi/3-Tier-MERN-App:ref:refs/heads/main'
```

**Root Cause:** GitHub Actions workflows with `environment: production` generate subject claim `environment:production`, but workflows without environment generate `ref:refs/heads/main`. The federated identity credential must match exactly.

**Resolution:**
Added `environment: production` to all jobs requiring Azure authentication:
```yaml
jobs:
  push-to-acr:
    environment: production  # This line was missing
```

This ensures consistent subject claim across all workflows.

**Lesson Learned:** OIDC subject claims are highly specific. Document the expected claim format and ensure all workflows use consistent patterns.

---

### Issue 2: Cosmos DB Authentication Failure

**Error:**
```
MongoServerError: Command Hello not supported prior to authentication
```

**Root Cause:** MongoDB driver's `serverApi` option is incompatible with Cosmos DB's MongoDB API implementation. Cosmos DB uses an older protocol version.

**Resolution:**
Modified connection configuration in `backend/db/connection.js`:
```javascript
// BEFORE (failed)
const client = new MongoClient(URI, {
  serverApi: {
    version: ServerApiVersion.v1,
    strict: true,
  },
});

// AFTER (works)
const client = new MongoClient(URI, {
  ssl: true,
  retryWrites: false,
});
```

Removed `serverApi` option and added Cosmos DB-specific options.

**Lesson Learned:** Managed database services often have API compatibility quirks. Always test connection logic early and read provider-specific documentation.

---

### Issue 3: nginx Permission Denied on Port 80

**Error:**
```
nginx: [emerg] bind() to 0.0.0.0:80 failed (13: Permission denied)
```

**Root Cause:** Attempted to run nginx as non-root user (uid 101) binding to privileged port 80. Linux restricts ports below 1024 to root.

**Initial Attempt:** Changed to port 8080 (non-privileged).

**Complication:** Required updating:
- nginx.conf
- Dockerfile EXPOSE
- Kubernetes containerPort
- Service targetPort
- Health check ports

**Final Resolution:** Simplified by allowing nginx to run as root for MVP deployment:
```yaml
# Removed securityContext constraints
# securityContext:
#   runAsNonRoot: true
#   runAsUser: 101
```

**Trade-off:** Less secure but significantly simpler. Can implement proper non-root configuration with capabilities later.

**Lesson Learned:** Security hardening introduces complexity. Balance security requirements against development velocity. Document security decisions for future improvement.

---

### Issue 4: Frontend CrashLoopBackOff

**Error:**
```
nginx: [emerg] mkdir() "/var/cache/nginx/client_temp" failed (13: Permission denied)
```

**Root Cause:** nginx cache directories not writable by non-root user.

**Resolution (Pre-Simplification):**
Added directory creation with proper ownership in Dockerfile:
```dockerfile
RUN mkdir -p /var/cache/nginx/client_temp \
             /var/cache/nginx/proxy_temp && \
    chown -R nginx:nginx /var/cache/nginx
```

**Lesson Learned:** Container images must be self-contained with all required directories and permissions. Kubernetes cannot fix filesystem permissions after container starts.

---

### Issue 5: Network Security Group Blocking Traffic

**Symptom:** LoadBalancer provisioned, pods healthy, but `http://<EXTERNAL-IP>` not accessible.

**Debugging Steps:**
1. Verified pods running: `kubectl get pods -n mern-app`
2. Verified service endpoints: `kubectl get endpoints -n mern-app`
3. Tested internal connectivity: `kubectl exec deployment/backend -- curl frontend-service`
4. All internal checks passed, external failed

**Root Cause:** Azure NSG (Network Security Group) on AKS subnet blocking inbound port 80 from internet.

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

**Lesson Learned:** Cloud networking has multiple layers (Kubernetes Services, Azure Load Balancers, NSGs, Firewalls). Systematic debugging from pod → service → load balancer → network rules is essential.

---

### Issue 6: API Requests Returning 502 Bad Gateway

**Symptom:** Frontend loads but data operations fail with 502 errors.

**Root Cause:** nginx proxy configuration not working. Backend service unreachable from frontend pods.

**Resolution:**
Updated nginx.conf with proper proxy configuration:
```nginx
location /api/ {
    rewrite ^/api/(.*)$ /$1 break;
    proxy_pass http://backend-service.mern-app.svc.cluster.local:5050;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
}
```

Key elements:
- `rewrite` strips `/api` prefix before forwarding
- Full FQDN for backend service
- Proper proxy headers for backend to see real client IP

**Lesson Learned:** API gateway patterns require careful URL rewriting and header forwarding. Test proxy configurations thoroughly.

---

## Security Considerations

### Current Security Posture

**Implemented:**
1. Namespace isolation
2. Kubernetes Secrets for credentials
3. Azure AD OIDC for CI/CD authentication
4. Private backend service (ClusterIP)
5. Resource limits preventing resource exhaustion
6. Health checks for automatic recovery

**Not Yet Implemented:**
1. Network policies restricting pod-to-pod traffic
2. Pod Security Standards enforcement
3. Non-root container users
4. Image vulnerability scanning in admission control
5. WAF (Web Application Firewall)
6. TLS/HTTPS encryption
7. Azure Key Vault integration
8. RBAC for namespace-level access control

---

### Recommended Security Enhancements

#### Priority 1: TLS/HTTPS
**Current Risk:** All traffic unencrypted, credentials visible in transit.

**Implementation:**
- Install cert-manager
- Create Ingress with TLS configuration
- Use Let's Encrypt for automatic certificate renewal

**Impact:** Encrypts all external traffic, enables browser security features.

---

#### Priority 2: Network Policies
**Current Risk:** Any pod can communicate with any other pod.

**Implementation:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-policy
spec:
  podSelector:
    matchLabels:
      app: backend
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 5050
```

**Impact:** Restricts backend to only accept traffic from frontend pods.

---

#### Priority 3: Non-Root Containers
**Current Risk:** Containers run as root, increasing attack surface.

**Implementation:** Already attempted, requires proper directory permissions and port changes. Can be revisited with user namespace support.

---

#### Priority 4: Secret Rotation
**Current Risk:** Static credentials never change.

**Implementation:**
- Integrate Azure Key Vault CSI driver
- Enable automatic secret rotation
- Update pods automatically on secret change

---

## Deployment Workflow

### Initial Deployment
```bash
# Apply in order
kubectl apply -f 00-namespace.yaml
kubectl apply -f 01-secret.yaml
kubectl apply -f 02-backend-deployment.yaml
kubectl apply -f 03-backend-service.yaml
kubectl apply -f 04-frontend-deployment.yaml
kubectl apply -f 05-frontend-service.yaml
```

### Update Deployment
```bash
# Update image version in deployment YAML
# Apply specific deployment
kubectl apply -f 02-backend-deployment.yaml

# Watch rollout
kubectl rollout status deployment/backend -n mern-app
```

### Rollback Deployment
```bash
# Rollback to previous version
kubectl rollout undo deployment/backend -n mern-app

# Rollback to specific revision
kubectl rollout undo deployment/backend --to-revision=2 -n mern-app
```

### Check Deployment History
```bash
kubectl rollout history deployment/backend -n mern-app
```

---

## Verification Commands

### Check All Resources
```bash
kubectl get all -n mern-app
```

### Check Pod Logs
```bash
# Specific pod
kubectl logs <pod-name> -n mern-app

# All pods for a deployment
kubectl logs deployment/backend -n mern-app

# Follow logs
kubectl logs -f deployment/backend -n mern-app
```

### Check Pod Details
```bash
kubectl describe pod <pod-name> -n mern-app
```

### Execute Commands in Pod
```bash
# Open shell
kubectl exec -it <pod-name> -n mern-app -- /bin/sh

# Run single command
kubectl exec <pod-name> -n mern-app -- curl http://localhost:5050/health
```

### Check Service Endpoints
```bash
kubectl get endpoints -n mern-app
```

### Check Secret Contents (Debug Only)
```bash
# Decode secret
kubectl get secret cosmos-secret -n mern-app -o jsonpath='{.data.mongodb-uri}' | base64 -d
```

---

## Conclusion

This manifest set provides a production-ready foundation for a 3-tier MERN application on Azure Kubernetes Service. The architecture prioritizes high availability, proper resource management, and clear separation of concerns.

Key achievements:
- Zero-downtime deployments via rolling updates
- Automatic health monitoring and recovery
- Secure credential management
- Scalable architecture supporting horizontal scaling
- Clear service boundaries and networking

Future enhancements should focus on security hardening (TLS, network policies, non-root containers), observability (Prometheus, Grafana), and GitOps automation (ArgoCD).

The issues encountered and resolved during implementation highlight the importance of systematic debugging, understanding cloud-native networking layers, and balancing security with operational simplicity.

---

**Document Version:** 1.0  
**Last Updated:** December 17, 2025  
**Author:** Akingbade Omosebi