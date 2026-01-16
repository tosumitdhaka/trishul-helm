# Trishul - Kubernetes Deployment Guide

This guide covers deploying Trishul on Kubernetes using Helm charts.

---

## **Prerequisites**
- Kubernetes cluster 1.20+ (Kind, Minikube, EKS, GKE, AKS, or on-prem)
- kubectl configured to access your cluster
- Helm 3.0+
- Docker images built and available (see README-DOCKER.md)
- 4GB+ RAM available in cluster
- 15GB+ storage available

---

## **Quick Start**

### 1. **Build Docker Images**
```bash
cd docker
docker build -f Dockerfile.backend -t trishul/trishul-backend:1.5.1 ..
docker build -f Dockerfile.frontend -t trishul/trishul-frontend:1.5.1 ..
```

### 2. **Load Images into Cluster (Kind/Minikube)**
For Kind cluster:
```bash
kind load docker-image trishul/trishul-backend:1.5.1
kind load docker-image trishul/trishul-frontend:1.5.1
```

For Minikube:
```bash
minikube image load trishul/trishul-backend:1.5.1
minikube image load trishul/trishul-frontend:1.5.1
```

For cloud providers (EKS, GKE, AKS), push to container registry:
```bash
docker tag trishul/trishul-backend:1.5.1 your-registry/trishul-backend:1.5.1
docker push your-registry/trishul-backend:1.5.1

docker tag trishul/trishul-frontend:1.5.1 your-registry/trishul-frontend:1.5.1
docker push your-registry/trishul-frontend:1.5.1
```
Update `values.yaml` with your registry URL.

### 3. **Install with Helm**
Install with default values:
```bash
helm install trishul ./trishul-helm
```

Install in specific namespace:
```bash
kubectl create namespace trishul
helm install trishul ./trishul-helm -n trishul
```

Install with custom values:
```bash
helm install trishul ./trishul-helm -f custom-values.yaml
```

### 4. **Verify Installation**
Check pod status:
```bash
kubectl get pods -l app.kubernetes.io/instance=trishul
```
Expected output:
```
NAME READY STATUS RESTARTS AGE
trishul-backend-xxxxxxxxxx-xxxxx 1/1 Running 0 2m
trishul-frontend-xxxxxxxxxx-xxxxx 1/1 Running 0 2m
trishul-mysql-0 1/1 Running 0 2m
```

Check services:
```bash
kubectl get svc -l app.kubernetes.io/instance=trishul
```
Expected output:
```
NAME TYPE CLUSTER-IP EXTERNAL-IP PORT(S) AGE
trishul-backend ClusterIP 10.96.xxx.xxx 8000/TCP 2m
trishul-frontend NodePort 10.96.xxx.xxx 80:30080/TCP 2m
trishul-mysql ClusterIP 10.96.xxx.xxx 3306/TCP 2m
trishul-trap-receiver NodePort 10.96.xxx.xxx 1162:30162/UDP 2m
```

Check PVCs:
```bash
kubectl get pvc -l app.kubernetes.io/instance=trishul
```
Expected output:
```
NAME STATUS VOLUME CAPACITY ACCESS MODES STORAGECLASS AGE
trishul-backend-data Bound pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx 5Gi RWO standard 2m
trishul-mysql-data Bound pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx 10Gi RWO standard 2m
```

---

## **Accessing the Application**

### Get Node IP
For Kind/Minikube:
```bash
export NODE_IP=$(kubectl get nodes -o jsonpath="{.items[0].status.addresses[0].address}")
echo $NODE_IP
```
For cloud providers, use external node IP or LoadBalancer IP.

### Access URLs
Frontend (Web UI):
```bash
echo "http://$NODE_IP:30080"
```
Open in browser: `http://<NODE_IP>:30080`

API Documentation:
```bash
echo "http://$NODE_IP:30080/docs"
```

SNMP Trap Receiver:
Send traps to: `<NODE_IP>:30162 (UDP)`

### Port Forwarding (Alternative)
If NodePort is not accessible, use port forwarding:
Frontend:
```bash
kubectl port-forward svc/trishul-frontend 8080:80
```
Access at: `http://localhost:8080`

Backend API:
```bash
kubectl port-forward svc/trishul-backend 8000:8000
```
Access at: `http://localhost:8000/api/v1/health`

---

## **Configuration**

### Customizing Values
Create a custom values file (`custom-values.yaml`):

Example 1: Change resource limits
```yaml
resources:
  backend:
    limits:
      memory: "4Gi"
      cpu: "4000m"
  mysql:
    limits:
      memory: "2Gi"
      cpu: "2000m"
```

Example 2: Change storage size
```yaml
persistence:
  mysql:
    size: 20Gi
  backend:
    size: 10Gi
```

Example 3: Change application config
```yaml
config:
  jobs:
    concurrency: 4
  cache:
    ttl_hours: 168
    max_size_mb: 1000
  logging:
    level: DEBUG
```

Example 4: Enable hostNetwork for port 162
```yaml
hostNetwork: true
```

Example 5: Change NodePort
```yaml
service:
  frontend:
    nodePort: 31080
  backend:
    trapNodePort: 31162
```

Apply custom values:
```bash
helm upgrade trishul ./trishul-helm -f custom-values.yaml
```

---

## **Helm Operations**
List Releases:
```bash
helm list
helm list -n trishul
```
Upgrade Release:
```bash
helm upgrade trishul ./trishul-helm
helm upgrade trishul ./trishul-helm -f custom-values.yaml
helm upgrade trishul ./trishul-helm --force
```
Rollback Release:
```bash
helm history trishul
helm rollback trishul
helm rollback trishul 2
```
Uninstall Release:
```bash
helm uninstall trishul
helm uninstall trishul --keep-history
kubectl delete pvc -l app.kubernetes.io/instance=trishul
```
Dry Run:
```bash
helm install trishul ./trishul-helm --dry-run --debug
```
Template Rendering:
```bash
helm template trishul ./trishul-helm
helm template trishul ./trishul-helm > rendered-manifests.yaml
```

---

## **Monitoring and Debugging**
View Logs:
```bash
kubectl logs -l app.kubernetes.io/component=backend -f
kubectl logs -l app.kubernetes.io/component=frontend -f
kubectl logs -l app.kubernetes.io/component=mysql -f
kubectl logs -l app.kubernetes.io/instance=trishul -f --all-containers
```
Describe Resources:
```bash
kubectl describe pod
kubectl describe svc trishul-frontend
kubectl describe pvc trishul-backend-data
```
Execute Commands in Pods:
```bash
kubectl exec -it <backend-pod> -- /bin/bash
kubectl exec -it trishul-mysql-0 -- /bin/bash
kubectl exec -it trishul-mysql-0 -- mysql -u root -ptrishul123
```
Check Events:
```bash
kubectl get events --sort-by=.metadata.creationTimestamp
kubectl get events -l app.kubernetes.io/instance=trishul
```
Health Checks:
```bash
kubectl exec -- curl -f http://localhost:8000/api/v1/health
kubectl exec -- wget -O- http://localhost/
```
Resource Usage:
```bash
kubectl top pods -l app.kubernetes.io/instance=trishul
kubectl top nodes
```

---

## **Production Best Practices**
- Use specific image tags (not latest)
- Set resource limits for all containers
- Enable persistence for all data
- Use secrets for sensitive data
- Configure backup automation
- Set up monitoring (Prometheus, Grafana)
- Configure log aggregation (EFK or Loki)
- Use Horizontal Pod Autoscaler
- Regular updates and security scanning

---

## **Support and Resources**
- Official Kubernetes documentation: https://kubernetes.io/docs/
- Helm documentation: https://helm.sh/docs/
- kubectl cheat sheet: https://kubernetes.io/docs/reference/kubectl/cheatsheet/
