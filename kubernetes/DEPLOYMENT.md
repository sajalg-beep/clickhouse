# Kubernetes YAML Deployment Guide

This guide explains how to deploy ClickHouse cluster using raw Kubernetes YAML manifests (without Terraform).

## Directory Structure

```
kubernetes/
├── base/                    # Base resources (namespaces, storage classes)
├── clickhouse/             # ClickHouse cluster manifests
├── zookeeper/              # ZooKeeper ensemble manifests
├── backup/                 # Backup CronJob and API manifests
├── monitoring/             # Prometheus monitoring manifests
└── kustomization.yaml      # Root kustomization file
```

## Prerequisites

### 1. GKE Cluster

You need an existing GKE cluster. Create one with:

```bash
gcloud container clusters create clickhouse-cluster \
  --region us-central1 \
  --node-locations us-central1-a,us-central1-b,us-central1-c \
  --num-nodes 1 \
  --machine-type n2-standard-8 \
  --disk-type pd-ssd \
  --disk-size 100 \
  --enable-autoscaling \
  --min-nodes 1 \
  --max-nodes 10 \
  --enable-autorepair \
  --enable-autoupgrade \
  --workload-pool=PROJECT_ID.svc.id.goog \
  --enable-shielded-nodes \
  --enable-network-policy
```

### 2. Install ClickHouse Operator

The ClickHouse Operator must be installed before deploying ClickHouse:

```bash
kubectl apply -f https://raw.githubusercontent.com/Altinity/clickhouse-operator/master/deploy/operator/clickhouse-operator-install-bundle.yaml
```

Verify operator is running:
```bash
kubectl get pods -n kube-system -l app=clickhouse-operator
```

### 3. Install Prometheus Operator (for monitoring)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

kubectl create namespace monitoring

helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false
```

## Deployment Methods

### Method 1: Deploy with Kustomize (Recommended)

Deploy everything at once:

```bash
# Review what will be created
kubectl kustomize kubernetes/

# Apply all resources
kubectl apply -k kubernetes/
```

Deploy specific components:

```bash
# Deploy only base resources
kubectl apply -k kubernetes/base/

# Deploy ZooKeeper
kubectl apply -k kubernetes/zookeeper/

# Deploy ClickHouse
kubectl apply -k kubernetes/clickhouse/

# Deploy backup system
kubectl apply -k kubernetes/backup/

# Deploy monitoring
kubectl apply -k kubernetes/monitoring/
```

### Method 2: Deploy with kubectl (Manual)

Deploy in order:

```bash
# 1. Base resources
kubectl apply -f kubernetes/base/namespaces.yaml
kubectl apply -f kubernetes/base/storage-class.yaml

# 2. ZooKeeper
kubectl apply -f kubernetes/zookeeper/service.yaml
kubectl apply -f kubernetes/zookeeper/statefulset.yaml
kubectl apply -f kubernetes/zookeeper/poddisruptionbudget.yaml

# Wait for ZooKeeper to be ready
kubectl wait --for=condition=ready pod -l app=zookeeper -n clickhouse --timeout=300s

# 3. ClickHouse
kubectl apply -f kubernetes/clickhouse/service-account.yaml
kubectl apply -f kubernetes/clickhouse/configmap.yaml
kubectl apply -f kubernetes/clickhouse/clickhouse-installation.yaml
kubectl apply -f kubernetes/clickhouse/service-lb.yaml

# Wait for ClickHouse to be ready
kubectl wait --for=condition=ready pod -l clickhouse.altinity.com/app=chop -n clickhouse --timeout=600s

# 4. Backup system
kubectl apply -f kubernetes/backup/service-account.yaml
kubectl apply -f kubernetes/backup/configmap.yaml
kubectl apply -f kubernetes/backup/cronjob.yaml
kubectl apply -f kubernetes/backup/deployment.yaml
kubectl apply -f kubernetes/backup/service.yaml

# 5. Monitoring
kubectl apply -f kubernetes/monitoring/servicemonitor.yaml
kubectl apply -f kubernetes/monitoring/prometheusrule.yaml
kubectl apply -f kubernetes/monitoring/grafana-dashboard-configmap.yaml
```

## Configuration

### Before Deployment

#### 1. Update Backup Configuration

Edit `kubernetes/backup/configmap.yaml` and set your GCS bucket name:

```yaml
gcs:
  bucket: YOUR_BACKUP_BUCKET_NAME  # Change this!
```

#### 2. Configure Workload Identity (Recommended for GKE)

Create GCP service accounts:

```bash
# For ClickHouse
gcloud iam service-accounts create clickhouse-sa \
  --display-name="ClickHouse Service Account"

# For Backup
gcloud iam service-accounts create clickhouse-backup-sa \
  --display-name="ClickHouse Backup Service Account"

# Grant GCS permissions to backup service account
gsutil mb gs://YOUR_BACKUP_BUCKET/
gsutil iam ch serviceAccount:clickhouse-backup-sa@PROJECT_ID.iam.gserviceaccount.com:objectAdmin gs://YOUR_BACKUP_BUCKET/

# Bind Kubernetes SA to GCP SA
gcloud iam service-accounts add-iam-policy-binding \
  clickhouse-sa@PROJECT_ID.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:PROJECT_ID.svc.id.goog[clickhouse/clickhouse-sa]"

gcloud iam service-accounts add-iam-policy-binding \
  clickhouse-backup-sa@PROJECT_ID.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:PROJECT_ID.svc.id.goog[clickhouse/clickhouse-backup-sa]"
```

Update service account annotations in:
- `kubernetes/clickhouse/service-account.yaml`
- `kubernetes/backup/service-account.yaml`

```yaml
annotations:
  iam.gke.io/gcp-service-account: clickhouse-sa@PROJECT_ID.iam.gserviceaccount.com
```

#### 3. Change Default Passwords

Edit `kubernetes/clickhouse/clickhouse-installation.yaml`:

```yaml
users:
  admin/password: "YOUR_SECURE_PASSWORD"
```

Also update password in:
- `kubernetes/backup/configmap.yaml`
- `kubernetes/backup/cronjob.yaml`
- `kubernetes/backup/deployment.yaml`

#### 4. Customize Cluster Size

Edit `kubernetes/clickhouse/clickhouse-installation.yaml`:

```yaml
clusters:
  - name: clickhouse-cluster
    layout:
      shardsCount: 2      # Number of shards
      replicasCount: 3    # Replicas per shard
```

Update resources:

```yaml
resources:
  requests:
    cpu: "4"           # Adjust as needed
    memory: "16Gi"     # Adjust as needed
```

## Verification

### Check Deployments

```bash
# Check all resources
kubectl get all -n clickhouse
kubectl get all -n monitoring

# Check ClickHouse Installation
kubectl get clickhouseinstallation -n clickhouse

# Check pods
kubectl get pods -n clickhouse -o wide

# Check services
kubectl get svc -n clickhouse
```

### Test ClickHouse Connection

```bash
# Port forward to ClickHouse
kubectl port-forward -n clickhouse svc/clickhouse-cluster 8123:8123 9000:9000

# Test HTTP interface
curl http://localhost:8123/ping

# Run a test query
echo "SELECT version()" | curl 'http://localhost:8123/?user=admin&password=changeme' --data-binary @-

# Or use clickhouse-client
clickhouse-client --host localhost --port 9000 --user admin --password changeme --query "SELECT version()"
```

### Check Cluster Status

```bash
# Execute query in ClickHouse pod
kubectl exec -n clickhouse chi-clickhouse-cluster-cluster-0-0-0 -- \
  clickhouse-client --query "SELECT * FROM system.clusters"

# Check replication
kubectl exec -n clickhouse chi-clickhouse-cluster-cluster-0-0-0 -- \
  clickhouse-client --query "SELECT * FROM system.replicas"
```

### Verify Backups

```bash
# Check CronJob
kubectl get cronjob -n clickhouse

# Check backup API
kubectl port-forward -n clickhouse svc/clickhouse-backup-api 7171:7171

# List backups
curl http://localhost:7171/backup/list

# Check GCS bucket
gsutil ls gs://YOUR_BACKUP_BUCKET/clickhouse-backups/
```

### Access Monitoring

```bash
# Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Open http://localhost:3000 (admin/admin)

# Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Open http://localhost:9090

# Check ServiceMonitors
kubectl get servicemonitor -n clickhouse

# Check PrometheusRules
kubectl get prometheusrule -n monitoring
```

## Scaling Operations

### Scale Replicas

Edit the ClickHouseInstallation:

```bash
kubectl edit clickhouseinstallation clickhouse-cluster -n clickhouse
```

Update `replicasCount` and save. The operator will handle rolling updates.

### Add Shards

Edit the ClickHouseInstallation and update `shardsCount`. Note: Adding shards doesn't automatically redistribute data.

### Scale Storage

```bash
# Check current PVC size
kubectl get pvc -n clickhouse

# Edit PVC (requires allowVolumeExpansion: true in StorageClass)
kubectl patch pvc data-volume-chi-clickhouse-cluster-cluster-0-0-0 \
  -n clickhouse \
  -p '{"spec":{"resources":{"requests":{"storage":"200Gi"}}}}'
```

## Upgrading ClickHouse Version

Edit `kubernetes/clickhouse/clickhouse-installation.yaml`:

```yaml
containers:
  - name: clickhouse
    image: clickhouse/clickhouse-server:24.1  # New version
```

Apply changes:

```bash
kubectl apply -f kubernetes/clickhouse/clickhouse-installation.yaml
```

The operator performs rolling updates automatically.

## Backup and Recovery

### Manual Backup

```bash
# Trigger backup via API
kubectl port-forward -n clickhouse svc/clickhouse-backup-api 7171:7171

curl -X POST http://localhost:7171/backup/create

# Or run backup job manually
kubectl create job --from=cronjob/clickhouse-backup manual-backup-$(date +%s) -n clickhouse
```

### Restore from Backup

```bash
# List available backups
kubectl exec -n clickhouse deployment/clickhouse-backup-api -- \
  clickhouse-backup list remote

# Restore
kubectl exec -n clickhouse deployment/clickhouse-backup-api -- \
  clickhouse-backup download backup-20240101-020000

kubectl exec -n clickhouse deployment/clickhouse-backup-api -- \
  clickhouse-backup restore backup-20240101-020000
```

## Troubleshooting

### ClickHouse Pods Not Starting

```bash
# Check pod events
kubectl describe pod -n clickhouse <pod-name>

# Check logs
kubectl logs -n clickhouse <pod-name>

# Check operator logs
kubectl logs -n kube-system -l app=clickhouse-operator
```

### ZooKeeper Issues

```bash
# Check ZooKeeper status
kubectl exec -n clickhouse zookeeper-0 -- zkServer.sh status

# Check logs
kubectl logs -n clickhouse zookeeper-0
```

### Backup Failures

```bash
# Check CronJob history
kubectl get jobs -n clickhouse

# Check backup pod logs
kubectl logs -n clickhouse -l job-name=clickhouse-backup-<timestamp>

# Verify GCS permissions
kubectl exec -n clickhouse deployment/clickhouse-backup-api -- \
  gcloud storage ls gs://YOUR_BACKUP_BUCKET/
```

## Clean Up

### Delete Everything

```bash
# Using Kustomize
kubectl delete -k kubernetes/

# Or manually
kubectl delete namespace clickhouse
kubectl delete namespace monitoring
kubectl delete -f kubernetes/base/storage-class.yaml
```

### Delete PVCs (Warning: Data Loss!)

```bash
kubectl delete pvc --all -n clickhouse
```

## Production Recommendations

1. **Change all default passwords** before production use
2. **Enable Workload Identity** for secure GCP access
3. **Set up proper monitoring alerts** via Alertmanager
4. **Configure backup notifications** for failure alerts
5. **Use ResourceQuotas** to limit resource usage
6. **Enable Pod Security Policies** or Pod Security Standards
7. **Set up Network Policies** to restrict traffic
8. **Use separate node pools** for ClickHouse workloads
9. **Enable audit logging** for compliance
10. **Regular backup testing** - verify restores work

## Next Steps

- Configure AlertManager for notifications (Slack, PagerDuty, etc.)
- Set up ingress for external access
- Configure TLS/SSL certificates
- Implement authentication and authorization
- Set up data retention policies
- Configure query limits and resource quotas
- Implement disaster recovery procedures
