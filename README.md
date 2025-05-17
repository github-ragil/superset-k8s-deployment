# Kubernetes Superset Deployment with Nginx Reverse Proxy

![Superset Logo](https://superset.apache.org/img/superset-logo-horiz-apache.svg)

This repository provides automated scripts to deploy:
- A production-ready Kubernetes cluster
- Apache Superset (latest version)
- Nginx reverse proxy with proper configuration

## 📋 Prerequisites

- **OS**: Ubuntu 24.04 
- **Resources**: Minimum 4GB RAM, 2 CPU cores, 40GB disk
- **Permissions**: Root/sudo access
- **Internet Connection without Proxy**

## 🚀 Quick Start

### 1. Clone this repository
```bash
git clone https://github.com/github-ragil/superset-k8s-deployment.git
cd superset-k8s-deployment
```
### 2. Make scripts executable
```bash
chmod +x setup-k8s.sh setup-superset-nginx.sh
```

### 3. Run the deployment (two-step process)
Step 1: Kubernetes Setup
```bash
./setup-k8s.sh
```
Verify all pods are running:

```bash
kubectl get pods -A -w
```
Wait until all pods show "Running" status

Step 2: Superset + Nginx Installation
```bash
./setup-superset-nginx.sh
```

# 🌐 Accessing Superset
After successful installation, access via:

Direct NodePort:

http://ip-public:30037

Through Nginx (Recommended):

http://ip-public

Default admin credentials:

Username: admin

Password: admin

# 🔍 Verification Commands
Check all components:

Check pods
```bash
kubectl get pods -A
```
Check services
```bash
kubectl get svc -A
```

Check persistent volumes
```bash
kubectl get pv,pvc -A
```

# 🛠️ Troubleshooting
Common issues and fixes:

Nginx not starting:

```bash
kubectl logs nginx-reverse-proxy -n default
```

Superset pods crashing:

```bash
kubectl logs -n superset <superset-pod-name> --previous
```
Port conflicts:

```bash
sudo netstat -tulnp | grep -E '80|30037'
```
# 🧹 Cleanup
To completely remove the deployment:


Remove Superset
```bash
helm uninstall superset -n superset
kubectl delete namespace superset
```

Remove Nginx
```bash
kubectl delete pod nginx-reverse-proxy -n nginx
kubectl delete configmap nginx-config -n nginx
```
