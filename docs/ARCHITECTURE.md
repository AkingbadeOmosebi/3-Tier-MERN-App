# System Architecture Diagram

**Project:** 3-Tier MERN Application on Azure Kubernetes Service  
**Author:** Akingbade Omosebi  
**Date:** December 2025

---

## Complete System Architecture

```
                                    ┌──────────────────────────────────────────────────────┐
                                    │                    INTERNET                          │
                                    └──────────────────────┬───────────────────────────────┘
                                                           │
                                                           │ HTTPS (443)
                                                           │ HTTP  (80)
                                                           │
                    ┌──────────────────────────────────────┼──────────────────────────────────────┐
                    │                     Azure Cloud      │                                      │
                    │  ┌────────────────────────────────────────────────────────────────────┐     │
                    │  │              Network Security Group (NSG)                          │     │
                    │  │  Rules:                                                            │     │
                    │  │    - allow-http:  Priority 100, Port 80  (Inbound)                 │     │
                    │  │    - allow-https: Priority 110, Port 443 (Inbound)                 │     │
                    │  └───────────────────────────┬────────────────────────────────────────┘     │
                    │                              │                                              │
                    │  ┌───────────────────────────┼──────────────────────────────────────┐       │
                    │  │     Azure Load Balancer   │                                      │       │
                    │  │     Public IP: 172.199.124.213                                   │       │
                    │  │                           │                                      │       │
                    │  │     Health Probe: //healthz                                      │       │
                    │  └───────────────────────────┼──────────────────────────────────────┘       │
                    │                              │                                              │
        ┌───────────┼──────────────────────────────┼──────────────────────────────────────────┐   │
        │           │  Azure Kubernetes Service    │                                          │   │
        │           │        (AKS Cluster)         │                                          │   │
        │           │                              │                                          │   │
        │  ┌────────┼──────────────────────────────┼──────────────────────────────────────┐   │   │
        │  │        │   Namespace: ingress-nginx   │                                      │   │   │
        │  │        │                              │                                      │   │   │
        │  │  ┌─────▼─────────────────────────────▼───────────────────────────────────┐   │   │   │
        │  │  │                                                                       │   │   │   │
        │  │  │           nginx Ingress Controller Pod                                │   │   │   │
        │  │  │                                                                       │   │   │   │
        │  │  │  Routes traffic based on:                                             │   │   │   │
        │  │  │    - Host: mern.ak-cloudtechdigital-az.info    → frontend-service     │   │   │   │
        │  │  │    - Host: argocd.ak-cloudtechdigital-az.info  → argocd-server        │   │   │   │
        │  │  │    - Host: grafana.ak-cloudtechdigital-az.info → grafana-service      │   │   │   │
        │  │  │                                                                       │   │   │   │
        │  │  │  TLS Termination:                                                     │   │   │   │
        │  │  │    - Reads certs from Secrets (auto-created by cert-manager)          │   │   │   │
        │  │  │    - Enforces HTTPS redirect                                          │   │   │   │
        │  │  │                                                                       │   │   │   │
        │  │  └──────────────────────────┬──────────────┬────────────┬────────────────┘   │   │   │
        │  │                             │              │            │                    │   │   │
        │  └─────────────────────────────┼──────────────┼────────────┼────────────────────┘   │   │
        │                                │              │            │                        │   │
        │  ┌─────────────────────────────┼──────────────┼────────────┼────────────────────┐   │   │
        │  │  Namespace: cert-manager    │              │            │                    │   │   │
        │  │                             │              │            │                    │   │   │
        │  │  ┌──────────────────────────▼───────┐      │            │                    │   │   │
        │  │  │   cert-manager Controller        │      │            │                    │   │   │
        │  │  │                                  │      │            │                    │   │   │
        │  │  │   - Watches Ingress resources    │      │            │                    │   │   │
        │  │  │   - Requests certs from Let's    │      │            │                    │   │   │
        │  │  │     Encrypt via ACME HTTP-01     │      │            │                    │   │   │
        │  │  │   - Stores certs in Secrets      │      │            │                    │   │   │
        │  │  │   - Auto-renews 30 days before   │      │            │                    │   │   │
        │  │  │     expiration                   │      │            │                    │   │   │
        │  │  │                                  │      │            │                    │   │   │
        │  │  │   ClusterIssuer:                 │      │            │                    │   │   │
        │  │  │     letsencrypt-prod             │      │            │                    │   │   │
        │  │  └──────────────────────────────────┘      │            │                    │   │   │
        │  │                                            │            │                    │   │   │
        │  └────────────────────────────────────────────┼────────────┼────────────────────┘   │   │
        │                                               │            │                        │   │
        │  ┌────────────────────────────────────────────┼────────────┼────────────────────┐   │   │
        │  │  Namespace: mern-app                       │            │                    │   │   │
        │  │                                            │            │                    │   │   │
        │  │  ┌─────────────────────────────────────────▼──────┐     │                    │   │   │
        │  │  │   frontend-service (ClusterIP: 10.1.153.150)   │     │                    │   │   │
        │  │  │   Port: 80                                     │     │                    │   │   │
        │  │  └──────────────┬──────────────┬──────────────────┘     │                    │   │   │
        │  │                 │              │                        │                    │   │   │
        │  │   ┌─────────────▼─┐  ┌────────▼────────┐  ┌───────────▼──────┐               │   │   │
        │  │   │  frontend-pod  │  │  frontend-pod   │  │  frontend-pod    │              │   │   │
        │  │   │                │  │                 │  │                  │              │   │   │
        │  │   │  Image:        │  │  Image:         │  │  Image:          │              │   │   │
        │  │   │  frontend:     │  │  frontend:      │  │  frontend:       │              │   │   │
        │  │   │  v1.11.0       │  │  v1.11.0        │  │  v1.11.0         │              │   │   │
        │  │   │                │  │                 │  │                  │              │   │   │
        │  │   │  Container:    │  │  Container:     │  │  Container:      │              │   │   │
        │  │   │  - React SPA   │  │  - React SPA    │  │  - React SPA     │              │   │   │
        │  │   │  - nginx:alpine│  │  - nginx:alpine │  │  - nginx:alpine  │              │   │   │
        │  │   │                │  │                 │  │                  │              │   │   │
        │  │   │  Resources:    │  │  Resources:     │  │  Resources:      │              │   │   │
        │  │   │  - CPU: 250m   │  │  - CPU: 250m    │  │  - CPU: 250m     │              │   │   │
        │  │   │  - Mem: 256Mi  │  │  - Mem: 256Mi   │  │  - Mem: 256Mi    │              │   │   │
        │  │   │                │  │                 │  │                  │              │   │   │
        │  │   │  Health Checks:│  │  Health Checks: │  │  Health Checks:  │              │   │   │
        │  │   │  - Readiness:/ │  │  - Readiness: / │  │  - Readiness: /  │              │   │   │
        │  │   │  - Liveness: / │  │  - Liveness: /  │  │  - Liveness: /   │              │   │   │
        │  │   └────────────────┘  └─────────────────┘  └──────────────────┘              │   │   │
        │  │                                                                              │   │   │
        │  │                             Proxies to ↓                                     │   │   │
        │  │                                                                              │   │   │
        │  │  ┌──────────────────────────────────────────────────────────────┐            │   │   │
        │  │  │   backend-service (ClusterIP: 10.1.218.207)                  │            │   │   │
        │  │  │   Port: 5050                                                 │            │   │   │
        │  │  └──────────────┬──────────────┬────────────────────────────────┘            │   │   │
        │  │                 │              │                                             │   │   │
        │  │   ┌─────────────▼─┐  ┌────────▼────────┐  ┌────────────────────┐             │   │   │
        │  │   │  backend-pod   │  │  backend-pod    │  │  backend-pod       │            │   │   │ 
        │  │   │                │  │                 │  │                    │            │   │   │
        │  │   │  Image:        │  │  Image:         │  │  Image:            │            │   │   │
        │  │   │  backend:      │  │  backend:       │  │  backend:          │            │   │   │
        │  │   │  v1.11.0       │  │  v1.11.0        │  │  v1.11.0           │            │   │   │
        │  │   │                │  │                 │  │                    │            │   │   │
        │  │   │  Container:    │  │  Container:     │  │  Container:        │            │   │   │
        │  │   │  - Node.js     │  │  - Node.js      │  │  - Node.js         │            │   │   │
        │  │   │  - Express API │  │  - Express API  │  │  - Express API     │            │   │   │
        │  │   │                │  │                 │  │                    │            │   │   │
        │  │   │  Resources:    │  │  Resources:     │  │  Resources:        │            │   │   │
        │  │   │  - CPU: 250m   │  │  - CPU: 250m    │  │  - CPU: 250m       │            │   │   │
        │  │   │  - Mem: 256Mi  │  │  - Mem: 256Mi   │  │  - Mem: 256Mi      │            │   │   │
        │  │   │                │  │                 │  │                    │            │   │   │
        │  │   │  Env (Secret): │  │  Env (Secret):  │  │  Env (Secret):     │            │   │   │
        │  │   │  - MONGODB_URI │  │  - MONGODB_URI  │  │  - MONGODB_URI     │            │   │   │
        │  │   │  - DB_NAME     │  │  - DB_NAME      │  │  - DB_NAME         │            │   │   │
        │  │   │                │  │                 │  │                    │            │   │   │
        │  │   │  Health:       │  │  Health:        │  │  Health:           │            │   │   │
        │  │   │  /health       │  │  /health        │  │  /health           │            │   │   │
        │  │   └────────┬───────┘  └──────┬──────────┘  └────────┬───────────┘            │   │   │
        │  │            │                 │                      │                        │   │   │
        │  │            └─────────────────┴──────────────────────┘                        │   │   │
        │  │                                   │                                          │   │   │
        │  │                                   │ Private Endpoint                         │   │   │
        │  │                                   │ IP: 10.0.2.4                             │   │   │
        │  │                                   │                                          │   │   │
        │  └───────────────────────────────────┼──────────────────────────────────────────┘   │   │
        │                                      │                                              │   │
        │  ┌────────────────────────────────────────────────────────────────────────────┐     │   │
        │  │  Namespace: argocd                │                                        │     │   │
        │  │                                   │                                        │     │   │
        │  │  ┌────────────────────────────────┼─────────────────────────────────────┐  │     │   │
        │  │  │   ArgoCD Server                │                                     │  │     │   │
        │  │  │   (ClusterIP Service)          │                                     │  │     │   │
        │  │  │                                │                                     │  │     │   │
        │  │  │   Exposed via Ingress at:      │                                     │  │     │   │
        │  │  │   https://argocd.ak-cloudtechdigital-az.info                         │  │     │   │
        │  │  └────────────────────────────────┼─────────────────────────────────────┘  │     │   │
        │  │                                   │                                        │     │   │
        │  │  ┌────────────────────────────────▼─────────────────────────────────────┐  │     │   │
        │  │  │   ArgoCD Application Controller                                      │  │     │   │
        │  │  │                                                                      │  │     │   │
        │  │  │   Monitors:                                                          │  │     │   │
        │  │  │   - GitHub Repo: 3-Tier-MERN-App                                     │  │     │   │
        │  │  │   - Path: k8s-manifests                                              │  │     │   │
        │  │  │   - Branch: main                                                     │  │     │   │
        │  │  │                                                                      │  │     │   │
        │  │  │   Sync Policy:                                                       │  │     │   │
        │  │  │   - Automated: true                                                  │  │     │   │
        │  │  │   - Self-Heal: true                                                  │  │     │   │
        │  │  │   - Prune: true                                                      │  │     │   │
        │  │  │                                                                      │  │     │   │
        │  │  │   Polls every 3 minutes for Git changes                              │  │     │   │
        │  │  │   Automatically applies changes to mern-app namespace                │  │     │   │
        │  │  │                                                                      │  │     │   │
        │  │  └──────────────────────────────────────────────────────────────────────┘  │     │   │
        │  │                                                                            │     │   │
        │  └────────────────────────────────────────────────────────────────────────────┘     │   │
        │                                                                                     │   │
        │  ┌──────────────────────────────────────────────────────────────────────────────┐   │   │
        │  │  Namespace: monitoring                                                       │   │   │
        │  │                                                                              │   │   │
        │  │  ┌─────────────────────────────────────────────────────────────────┐         │   │   │
        │  │  │   Prometheus Server (StatefulSet)                               │         │   │   │
        │  │  │                                                                 │         │   │   │
        │  │  │   - Scrapes metrics from ServiceMonitors                        │         │   │   │
        │  │  │   - Time-series database                                        │         │   │   │
        │  │  │   - Evaluates PrometheusRules                                   │         │   │   │
        │  │  │   - Sends alerts to Alertmanager                                │         │   │   │
        │  │  │                                                                 │         │   │   │
        │  │  │   Monitors:                                                     │         │   │   │
        │  │  │   - mern-app namespace (backend-monitor, frontend-monitor)      │         │   │   │
        │  │  │   - All cluster nodes (node-exporter)                           │         │   │   │
        │  │  │   - Kubernetes objects (kube-state-metrics)                     │         │   │   │
        │  │  │                                                                 │         │   │   │
        │  │  └──────────────────────────┬──────────────────────────────────────┘         │   │   │
        │  │                             │                                                │   │   │
        │  │  ┌──────────────────────────▼───────────────────────────────────────┐        │   │   │
        │  │  │   Grafana (Deployment)                                           │        │   │   │
        │  │  │   (ClusterIP Service)                                            │        │   │   │
        │  │  │                                                                  │        │   │   │
        │  │  │   Exposed via Ingress at:                                        │        │   │   │
        │  │  │   https://grafana.ak-cloudtechdigital-az.info                    │        │   │   │
        │  │  │                                                                  │        │   │   │
        │  │  │   Dashboards:                                                    │        │   │   │
        │  │  │   - Kubernetes Views - Pods (ID: 15760)                          │        │   │   │
        │  │  │   - Kubernetes Views - Namespaces (ID: 15758)                    │        │   │   │
        │  │  │   - Kubernetes Views - Global (ID: 15757)                        │        │   │   │
        │  │  │                                                                  │        │   │   │
        │  │  │   Data Source: Prometheus                                        │        │   │   │
        │  │  │                                                                  │        │   │   │
        │  │  └──────────────────────────────────────────────────────────────────┘        │   │   │
        │  │                                                                              │   │   │
        │  │  ┌────────────────────────────────────────────────────────────────┐          │   │   │
        │  │  │   Alertmanager (StatefulSet)                                   │          │   │   │
        │  │  │                                                                │          │   │   │
        │  │  │   Receives alerts from Prometheus                              │          │   │   │ 
        │  │  │   Routes alerts based on labels                                │          │   │   │
        │  │  │   (No notification channels configured yet)                    │          │   │   │
        │  │  │                                                                │          │   │   │
        │  │  └────────────────────────────────────────────────────────────────┘          │   │   │
        │  │                                                                              │   │   │
        │  │  ┌────────────────────────────────────────────────────────────────┐          │   │   │
        │  │  │   Node Exporters (DaemonSet - 1 per node)                      │          │   │   │
        │  │  │                                                                │          │   │   │
        │  │  │   Expose hardware and OS metrics:                              │          │   │   │
        │  │  │   - CPU usage, temperature                                     │          │   │   │
        │  │  │   - Memory usage, swap                                         │          │   │   │
        │  │  │   - Disk I/O, space                                            │          │   │   │
        │  │  │   - Network interfaces                                         │          │   │   │
        │  │  │                                                                │          │   │   │
        │  │  └────────────────────────────────────────────────────────────────┘          │   │   │
        │  │                                                                              │   │   │
        │  │  ┌────────────────────────────────────────────────────────────────┐          │   │   │
        │  │  │   kube-state-metrics (Deployment)                              │          │   │   │
        │  │  │                                                                │          │   │   │
        │  │  │   Exposes Kubernetes object state:                             │          │   │   │
        │  │  │   - Pod status, restarts                                       │          │   │   │
        │  │  │   - Deployment replicas                                        │          │   │   │
        │  │  │   - Node conditions                                            │          │   │   │
        │  │  │   - Resource requests/limits                                   │          │   │   │
        │  │  │                                                                │          │   │   │
        │  │  └────────────────────────────────────────────────────────────────┘          │   │   │
        │  │                                                                              │   │   │
        │  └──────────────────────────────────────────────────────────────────────────────┘   │   │ 
        │                                                                                     │   │
        │                                                                                     │   │
        │  ┌──────────────────────────────────────────────────────────────────────────────┐   │   │
        │  │  Cluster Infrastructure                                                      │   │   │
        │  │                                                                              │   │   │
        │  │  Node Pools:                                                                 │   │   │
        │  │  ┌────────────────────────┐  ┌────────────────────────┐                      │   │   │
        │  │  │  System Node Pool      │  │  User Node Pool        │                      │   │   │
        │  │  │  - 3 nodes             │  │  - 3 nodes             │                      │   │   │
        │  │  │  - Standard_D2s_v3     │  │  - Standard_D2s_v3     │                      │   │   │
        │  │  │  - System workloads    │  │  - Application pods    │                      │   │   │
        │  │  └────────────────────────┘  └────────────────────────┘                      │   │   │
        │  │                                                                              │   │   │
        │  │  Virtual Network: vnet-3tier-mern (10.0.0.0/16)                              │   │   │
        │  │  ┌────────────────────────────────────────────────────────────────┐          │   │   │
        │  │  │  Subnets:                                                      │          │   │   │
        │  │  │  - aks-nodes: 10.0.1.0/24                                      │          │   │   │
        │  │  │  - aks-pods: 10.0.4.0/22                                       │          │   │   │
        │  │  │  - private-endpoints: 10.0.2.0/25                              │          │   │   │
        │  │  └────────────────────────────────────────────────────────────────┘          │   │   │
        │  │                                                                              │   │   │
        │  └──────────────────────────────────────────────────────────────────────────────┘   │   │
        │                                                                                     │   │
        └─────────────────────────────────────────────────────────────────────────────────────┘   │
                                                                                                  │
                                             │                                                    │
                                             │ Private Endpoint                                   │
                                             │ IP: 10.0.2.4                                       │
                                             │ MongoDB Protocol (10255)                           │
                                             │ SSL: true                                          │
                                             │ retryWrites: false                                 │
                                             │                                                    │
        ┌────────────────────────────────────┼────────────────────────────────────────┐           │
        │  Azure Managed Services            │                                        │           │
        │                                    │                                        │           │
        │  ┌─────────────────────────────────▼──────────────────────────────────────┐ │           │
        │  │   Azure Cosmos DB (MongoDB API)                                        │ │           │
        │  │                                                                        │ │           │
        │  │   Account: cosmos-3tier-mern-ao-pol9db                                 │ │           │
        │  │   Database: merndb                                                     │ │           │
        │  │   Connection: Private Endpoint (10.0.2.4)                              │ │           │
        │  │                                                                        │ │           │
        │  │   Features:                                                            │ │           │
        │  │   - Global distribution                                                │ │           │
        │  │   - Automatic replication                                              │ │           │
        │  │   - 99.999% availability SLA                                           │ │           │
        │  │   - Automatic indexing                                                 │ │           │
        │  │                                                                        │ │           │
        │  └────────────────────────────────────────────────────────────────────────┘ │           │
        │                                                                             │           │
        │  ┌────────────────────────────────────────────────────────────────────────┐ │           │
        │  │   Azure Container Registry                                             │ │           │
        │  │                                                                        │ │           │
        │  │   Registry: acr3tiermernappao.azurecr.io                               │ │           │
        │  │                                                                        │ │           │
        │  │   Images:                                                              │ │           │
        │  │   - backend:v1.11.0                                                    │ │           │
        │  │   - frontend:v1.11.0                                                   │ │           │
        │  │                                                                        │ │           │
        │  │   Pushed via GitHub Actions CI/CD pipeline                             │ │           │
        │  │                                                                        │ │           │
        │  └────────────────────────────────────────────────────────────────────────┘ │           │
        │                                                                             │           │
        └─────────────────────────────────────────────────────────────────────────────┘           │
                                                                                                  │
                                                                                                  │
┌─────────────────────────────────────────────────────────────────────────────────────────────────┘
│  External Services
│
│  ┌────────────────────────────────────────────────────────────────┐
│  │   Let's Encrypt (ACME Server)                                  │
│  │                                                                │
│  │   Provides TLS certificates via ACME HTTP-01 challenge         │
│  │   Certificates valid for 90 days, auto-renewed at 60 days      │
│  │                                                                │
│  │   Certificates issued:                                         │
│  │   - mern.ak-cloudtechdigital-az.info                           │
│  │   - argocd.ak-cloudtechdigital-az.info                         │
│  │   - grafana.ak-cloudtechdigital-az.info                        │
│  │                                                                │
│  └────────────────────────────────────────────────────────────────┘
│
│  ┌────────────────────────────────────────────────────────────────┐
│  │   Namecheap DNS                                                │
│  │                                                                │
│  │   Domain: ak-cloudtechdigital-az.info                          │
│  │                                                                │
│  │   A Records → 172.199.124.213 (Ingress Controller IP):         │
│  │   - mern.ak-cloudtechdigital-az.info                           │
│  │   - argocd.ak-cloudtechdigital-az.info                         │
│  │   - grafana.ak-cloudtechdigital-az.info                        │
│  │                                                                │
│  └────────────────────────────────────────────────────────────────┘
│
│  ┌────────────────────────────────────────────────────────────────┐
│  │   GitHub Repository                                            │
│  │                                                                │
│  │   Repo: AkingbadeOmosebi/3-Tier-MERN-App                       │
│  │                                                                │
│  │   Monitored by:                                                │
│  │   - ArgoCD (polls every 3 minutes for manifest changes)        │
│  │   - GitHub Actions (triggers on push for CI/CD)                │
│  │                                                                │
│  │   Contains:                                                    │
│  │   - Application source code (backend, frontend)                │
│  │   - Kubernetes manifests (k8s-manifests/)                      │
│  │   - Terraform infrastructure code                              │
│  │   - CI/CD workflows (.github/workflows/)                       │
│  │                                                                │
│  └────────────────────────────────────────────────────────────────┘
│
└─────────────────────────────────────────────────────────────────────
```

---

## Traffic Flow Diagrams

### User Request Flow (Frontend)

```
User Browser
     │
     │ 1. HTTPS GET https://mern.ak-cloudtechdigital-az.info
     │
     ▼
Namecheap DNS
     │
     │ 2. DNS Resolution → 172.199.124.213
     │
     ▼
Azure NSG
     │
     │ 3. Allow HTTPS (Port 443) - Priority 110
     │
     ▼
Azure Load Balancer (172.199.124.213)
     │
     │ 4. Health Check: //healthz → Healthy
     │ 5. Forward to Ingress Controller Pod
     │
     ▼
nginx Ingress Controller
     │
     │ 6. Terminate TLS (cert from mern-tls-secret)
     │ 7. Parse Host header: mern.ak-cloudtechdigital-az.info
     │ 8. Route to backend: frontend-service
     │
     ▼
frontend-service (ClusterIP: 10.1.153.150)
     │
     │ 9. Load balance across 3 frontend pods
     │
     ▼
frontend-pod (1 of 3)
     │
     │ 10. nginx serves React SPA
     │ 11. Return HTML/JS/CSS
     │
     ▼
User Browser (renders application)
```

### API Request Flow (Backend)

```
React App in Browser
     │
     │ 1. JavaScript: fetch('/api/records')
     │
     ▼
nginx in frontend-pod
     │
     │ 2. Proxy rule: /api/* → backend-service:5050
     │ 3. Rewrite: /api/records → /records
     │
     ▼
backend-service (ClusterIP: 10.1.218.207)
     │
     │ 4. Load balance across 3 backend pods
     │
     ▼
backend-pod (1 of 3)
     │
     │ 5. Express API processes request
     │ 6. MongoDB driver connects to Cosmos DB
     │
     ▼
Private Endpoint (10.0.2.4)
     │
     │ 7. Route to Cosmos DB via private network
     │
     ▼
Azure Cosmos DB
     │
     │ 8. Query MongoDB API
     │ 9. Return documents
     │
     ▼
backend-pod
     │
     │ 10. Transform data, send JSON response
     │
     ▼
React App in Browser (updates UI)
```

### GitOps Deployment Flow

```
Developer
     │
     │ 1. Edit k8s-manifests/02-backend-deployment.yaml
     │ 2. Change image tag: v1.10.0 → v1.11.0
     │ 3. git commit -m "feat: Update backend to v1.11.0"
     │ 4. git push origin main
     │
     ▼
GitHub Repository (main branch)
     │
     │ 5. Commit stored with full history
     │
     ▼
ArgoCD Application Controller
     │
     │ 6. Poll GitHub every 3 minutes
     │ 7. Detect change: hash mismatch
     │ 8. Clone repository, parse manifests
     │ 9. Compare desired state vs actual state
     │ 10. Identify: Deployment image tag changed
     │
     ▼
Kubernetes API Server
     │
     │ 11. ArgoCD sends: PATCH Deployment backend
     │ 12. New image: backend:v1.11.0
     │
     ▼
Deployment Controller
     │
     │ 13. Rolling update strategy
     │ 14. Create new ReplicaSet with v1.11.0
     │ 15. Scale up new ReplicaSet (1 → 2 → 3)
     │ 16. Scale down old ReplicaSet (3 → 2 → 1 → 0)
     │ 17. Wait for readiness probes between each step
     │
     ▼
New backend-pod instances running v1.11.0
     │
     │ 18. Old pods terminated gracefully
     │ 19. Zero-downtime deployment complete
     │
     ▼
ArgoCD Application Status: Synced, Healthy
```

### Monitoring and Alerting Flow

```
MERN Application Pods
     │
     │ Expose metrics via health endpoints
     │
     ▼
ServiceMonitor Resources (backend-monitor, frontend-monitor)
     │
     │ Define scrape configuration
     │
     ▼
Prometheus Server
     │
     │ 1. Scrapes /health endpoint every 30s
     │ 2. Stores time-series metrics in TSDB
     │ 3. Evaluates PrometheusRules every 30s
     │
     ▼
PrometheusRule: MERNPodNotReady
     │
     │ expr: kube_pod_container_status_ready{namespace="mern-app"} == 0
     │ for: 2m
     │
     ▼
Alert State: PENDING → FIRING (after 2 minutes)
     │
     │ Labels: severity=critical, service=mern-portfolio
     │
     ▼
Alertmanager
     │
     │ Receives alert from Prometheus
     │ Routes based on labels
     │ (No notification channels configured yet)
     │
     ▼
Grafana Dashboards
     │
     │ Query Prometheus data source
     │ Display alert status in UI
     │ Visualize metrics in dashboards
     │
     ▼
Platform Engineer
     │
     │ Views alert in Grafana or Prometheus UI
     │ Investigates root cause
     │ Takes remediation action
```

### Certificate Acquisition Flow (ACME HTTP-01)

```
Ingress Resource Created
     │
     │ annotations:
     │   cert-manager.io/cluster-issuer: letsencrypt-prod
     │ tls:
     │   - hosts: [mern.ak-cloudtechdigital-az.info]
     │     secretName: mern-tls-secret
     │
     ▼
cert-manager Controller
     │
     │ 1. Detects new Ingress with cert-manager annotation
     │ 2. Checks if mern-tls-secret exists (no)
     │ 3. Creates Certificate resource
     │
     ▼
Certificate Resource
     │
     │ 4. Defines: domain, issuer, secret name
     │
     ▼
cert-manager Controller
     │
     │ 5. Creates CertificateRequest
     │ 6. Contacts Let's Encrypt ACME server
     │ 7. Requests certificate for mern.ak-cloudtechdigital-az.info
     │
     ▼
Let's Encrypt ACME Server
     │
     │ 8. Generates challenge token: abc123xyz
     │ 9. Returns challenge: HTTP-01
     │
     ▼
cert-manager Controller
     │
     │ 10. Creates temporary Ingress:
     │     /.well-known/acme-challenge/abc123xyz
     │ 11. Creates temporary Pod serving challenge response
     │
     ▼
Let's Encrypt ACME Server
     │
     │ 12. Makes HTTP GET request:
     │     http://mern.ak-cloudtechdigital-az.info/.well-known/acme-challenge/abc123xyz
     │
     ▼
nginx Ingress Controller
     │
     │ 13. Routes to challenge Pod
     │ 14. Returns challenge response
     │
     ▼
Let's Encrypt ACME Server
     │
     │ 15. Validates response matches expected value
     │ 16. Domain ownership confirmed
     │ 17. Issues certificate (valid 90 days)
     │
     ▼
cert-manager Controller
     │
     │ 18. Receives certificate from Let's Encrypt
     │ 19. Stores in Kubernetes Secret: mern-tls-secret
     │ 20. Cleans up temporary resources
     │
     ▼
nginx Ingress Controller
     │
     │ 21. Detects new Secret: mern-tls-secret
     │ 22. Loads certificate and private key
     │ 23. Configures HTTPS for mern.ak-cloudtechdigital-az.info
     │
     ▼
Certificate Status: READY=True
     │
     │ HTTPS now available
     │
     ▼
Users can access https://mern.ak-cloudtechdigital-az.info
```

---

## Component Interaction Matrix

| Component | Interacts With | Purpose |
|-----------|----------------|---------|
| nginx Ingress Controller | Azure LB, frontend-service, argocd-server, grafana | TLS termination, host-based routing |
| cert-manager | Ingress resources, Let's Encrypt, Kubernetes Secrets | Certificate lifecycle management |
| ArgoCD Controller | GitHub, Kubernetes API, mern-app namespace | GitOps synchronization |
| Prometheus | ServiceMonitors, Node Exporters, kube-state-metrics | Metrics collection |
| Grafana | Prometheus | Metrics visualization |
| Alertmanager | Prometheus | Alert routing (not yet configured) |
| backend-pod | frontend-pod (via service), Cosmos DB | API server, database client |
| frontend-pod | backend-service, users | React SPA, nginx reverse proxy |

---

**Architecture Version:** 1.0  
**Last Updated:** December 2025  
**Author:** Akingbade Omosebi
