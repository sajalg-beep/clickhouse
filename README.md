# Enterprise-Grade ClickHouse Cluster on GKE

This repository contains complete infrastructure code to deploy a production-ready, enterprise-grade ClickHouse cluster on Google Kubernetes Engine (GKE).

## Deployment Options

Choose your preferred deployment method:

### 🌟 Recommended: Hybrid Approach
**[Terraform + Kubernetes YAML](HYBRID_DEPLOYMENT.md)** - Best of both worlds
- ✅ Terraform manages GKE infrastructure, networking, and GCP resources
- ✅ Kubernetes YAML deploys ClickHouse with advanced scheduling features
- ✅ Fine-grained control over pod placement, topology, and rack awareness
- ✅ PodDisruptionBudgets for high availability
- ✅ Easy to customize and iterate

### Alternative Approaches

1. **[Terraform Only](terraform/)** - Full infrastructure automation (GKE + all components)
   - Manages everything including ClickHouse deployment via Helm
   - Good for: Fully automated deployments

2. **[Kubernetes YAML Only](kubernetes/DEPLOYMENT.md)** - Direct manifest deployment
   - Requires existing GKE cluster
   - Good for: When you manage GKE separately

## Features

### High Availability
- **Multi-Zone Deployment**: Replicas distributed across GCP availability zones
- **Topology Spread Constraints**: Automatic pod distribution across zones, racks, and nodes
- **Rack Awareness**: Custom node labeling for physical rack distribution
- **Pod Disruption Budgets**: Ensures minimum availability during maintenance (minAvailable: 2)
- **Pod Anti-Affinity**: Hard requirement - no replicas of same shard on same node

### Data Management
- **Replication**: Built-in data replication across replicas using ZooKeeper
- **Sharding**: Horizontal scaling with configurable number of shards
- **Automated Backups**: Scheduled backups to Google Cloud Storage (daily at 2 AM UTC)
- **Point-in-Time Recovery**: Restore from any backup with configurable retention (default: 30 days)
- **Backup API**: REST API for manual backup and restore operations

### Operations
- **Zero-Downtime Maintenance**: Rolling updates for version upgrades and configuration changes
- **Auto-scaling**: Node auto-scaling based on workload (1-10 nodes per zone)
- **Monitoring**: Prometheus and Grafana with pre-configured ClickHouse dashboards
- **Alerting**: 10+ alert rules for critical metrics (downtime, query performance, replication lag)
- **GitOps Ready**: Kustomize support for environment-specific configurations

### Security
- **Workload Identity**: Secure GCP access without service account keys
- **Network Policies**: Restrict pod-to-pod communication
- **Private GKE Cluster**: Nodes have no external IPs
- **Shielded Nodes**: Secure boot and integrity monitoring enabled
- **RBAC**: Kubernetes role-based access control

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    GKE Regional Cluster                  │
│                     (Multi-Zone HA)                      │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  ┌─────────────────────────────────────────────────┐   │
│  │          ClickHouse Cluster                      │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐      │   │
│  │  │ Shard 1  │  │ Shard 2  │  │ Shard N  │      │   │
│  │  │ Replica1 │  │ Replica1 │  │ Replica1 │      │   │
│  │  │ Replica2 │  │ Replica2 │  │ Replica2 │      │   │
│  │  │ Replica3 │  │ Replica3 │  │ Replica3 │      │   │
│  │  └──────────┘  └──────────┘  └──────────┘      │   │
│  └─────────────────────────────────────────────────┘   │
│                                                           │
│  ┌─────────────────────────────────────────────────┐   │
│  │         ZooKeeper Ensemble (3 nodes)             │   │
│  └─────────────────────────────────────────────────┘   │
│                                                           │
│  ┌─────────────────────────────────────────────────┐   │
│  │     Backup Service (CronJob + API)               │   │
│  └─────────────────────────────────────────────────┘   │
│                                                           │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Monitoring (Prometheus + Grafana + Alertmanager)│   │
│  └─────────────────────────────────────────────────┘   │
│                                                           │
└─────────────────────────────────────────────────────────┘
                        │
                        ▼
              ┌──────────────────┐
              │  Google Cloud    │
              │  Storage (GCS)   │
              │  Backups         │
              └──────────────────┘
```

## Quick Start

### 🌟 Recommended: Hybrid Deployment

**Phase 1: Infrastructure (Terraform)**

```bash
# 1. Configure Terraform
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project_id

# 2. Deploy GKE infrastructure
terraform init
terraform apply

# 3. Get credentials
eval $(terraform output -raw connect_to_cluster)
```

**Phase 2: ClickHouse (Kubernetes YAML)**

```bash
# 1. Install ClickHouse Operator
kubectl apply -f https://raw.githubusercontent.com/Altinity/clickhouse-operator/master/deploy/operator/clickhouse-operator-install-bundle.yaml

# 2. Label nodes for rack awareness
kubectl get nodes -o name | xargs -I {} kubectl label {} topology.clickhouse.com/rack=rack1 workload=clickhouse

# 3. Update service account annotations (from terraform outputs)
# Edit kubernetes/clickhouse/service-account.yaml
# Edit kubernetes/backup/service-account.yaml

# 4. Deploy ClickHouse
kubectl apply -k kubernetes/

# 5. Verify deployment
kubectl get pods -n clickhouse -o wide
```

**Total deployment time:** ~25 minutes

📖 **[Complete Hybrid Deployment Guide](HYBRID_DEPLOYMENT.md)**

### Alternative Methods

<details>
<summary>Option 1: Terraform Only (Click to expand)</summary>

**Note:** Uses Helm for ClickHouse deployment, less control over pod placement.

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

📖 [Terraform Documentation](terraform/)
</details>

<details>
<summary>Option 2: Kubernetes YAML Only (Click to expand)</summary>

**Note:** Requires existing GKE cluster.

```bash
# Requires: GKE cluster, ClickHouse Operator
kubectl apply -k kubernetes/
```

📖 [Kubernetes YAML Documentation](kubernetes/DEPLOYMENT.md)
</details>

## Prerequisites by Deployment Method

### For Terraform Deployment

1. **Google Cloud SDK** installed and configured
2. **Terraform** >= 1.5.0
3. **kubectl** installed
4. **Enabled GCP APIs**:
   - container.googleapis.com
   - compute.googleapis.com
   - storage-api.googleapis.com
5. **GCP Permissions**:
   - roles/container.admin
   - roles/compute.admin
   - roles/iam.serviceAccountAdmin
   - roles/storage.admin

### For Kubernetes YAML Deployment

1. **Existing GKE cluster** (or create one manually)
2. **kubectl** installed and configured
3. **ClickHouse Operator** (installation instructions in deployment guide)
4. **Prometheus Operator** (optional, for monitoring)

## Accessing ClickHouse

### Port Forward (for testing)

```bash
kubectl port-forward -n clickhouse svc/clickhouse-cluster 8123:8123 9000:9000
```

### Connect with clickhouse-client

```bash
# HTTP interface
curl http://localhost:8123/ping

# Native client
clickhouse-client --host localhost --port 9000 --user admin --password changeme
```

### Internal Access (from within cluster)

```
Host: clickhouse-cluster.clickhouse.svc.cluster.local
HTTP Port: 8123
TCP Port: 9000
Username: admin
Password: changeme
```

## Backup and Recovery

### Automated Backups

Backups run automatically according to the schedule defined in `backup_schedule` (default: daily at 2 AM UTC).

View backup status:
```bash
kubectl get cronjob -n clickhouse
kubectl get jobs -n clickhouse
```

### Manual Backup

```bash
# Port forward to backup API
kubectl port-forward -n clickhouse svc/clickhouse-backup-api 7171:7171

# Trigger backup via API
curl -X POST http://localhost:7171/backup/create
```

### List Backups

```bash
# From backup API
curl http://localhost:7171/backup/list

# Or check GCS bucket directly
gsutil ls gs://YOUR_BACKUP_BUCKET/clickhouse-backups/
```

### Restore from Backup

```bash
# List available backups
kubectl exec -n clickhouse deployment/clickhouse-backup-api -- \
  clickhouse-backup list remote

# Restore specific backup
kubectl exec -n clickhouse deployment/clickhouse-backup-api -- \
  clickhouse-backup restore backup-20240101-020000
```

## Monitoring

### Access Grafana

```bash
# Port forward Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Open browser to http://localhost:3000
# Username: admin
# Password: admin (change in production)
```

### Pre-configured Dashboards

- **ClickHouse Overview**: General cluster metrics
- **ClickHouse Queries**: Query performance and statistics
- **Node Metrics**: Kubernetes node metrics
- **Pod Metrics**: Container resource usage

### Access Prometheus

```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Open browser to http://localhost:9090
```

### Alerting

Alerts are configured in `modules/monitoring/main.tf`. Current alerts:
- ClickHouse instance down
- High query duration
- Too many connections
- High disk usage
- Replication lag
- ZooKeeper connection loss

Configure notification channels in the Alertmanager config.

## Maintenance Operations

### Version Upgrade

1. Update `clickhouse_version` in `terraform.tfvars`:
   ```hcl
   clickhouse_version = "23.12"
   ```

2. Apply changes:
   ```bash
   terraform apply
   ```

The operator will perform a rolling update with zero downtime.

### Scale Storage

1. Update `clickhouse_storage_size` in `terraform.tfvars`:
   ```hcl
   clickhouse_storage_size = "200Gi"
   ```

2. Apply changes:
   ```bash
   terraform apply
   ```

Note: Storage can only be increased, not decreased.

### Scale Cluster (Add Shards/Replicas)

1. Update shard/replica count:
   ```hcl
   clickhouse_shards   = 4
   clickhouse_replicas = 3
   ```

2. Apply changes:
   ```bash
   terraform apply
   ```

### Node Pool Scaling

Update `node_pool_max_count` to allow more nodes:
```hcl
node_pool_max_count = 20
```

### Tune ClickHouse Settings

Edit the ConfigMap in `modules/clickhouse/main.tf` or use the ClickHouseInstallation custom resource:

```bash
kubectl edit clickhouseinstallation -n clickhouse clickhouse-cluster
```

Changes will trigger a rolling restart.

### GKE Cluster Upgrade

GKE will automatically upgrade during the maintenance window. To manually upgrade:

```bash
gcloud container clusters upgrade clickhouse-cluster \
  --region us-central1 \
  --cluster-version 1.28
```

## Security Best Practices

### Change Default Passwords

1. Update ClickHouse admin password in `modules/clickhouse/main.tf`
2. Update Grafana password in `modules/monitoring/main.tf`
3. Apply changes with `terraform apply`

### Enable Binary Authorization (Optional)

```hcl
enable_binary_authorization = true
```

This enforces only signed container images can run.

### Network Policies

Network policies are enabled by default to restrict pod-to-pod communication.

### Workload Identity

Workload Identity is enabled by default for secure GCP API access without service account keys.

## Disaster Recovery

### Full Cluster Recovery

1. Deploy new infrastructure with Terraform
2. List available backups:
   ```bash
   gsutil ls gs://YOUR_BACKUP_BUCKET/clickhouse-backups/
   ```
3. Restore from backup (see Backup and Recovery section)

### Point-in-Time Recovery

Backups include all data up to the backup time. Use the most recent backup before the desired recovery point.

## Cost Optimization

### Current Resource Usage

- **GKE Cluster**: 2 node pools (system + clickhouse)
- **ClickHouse**: Configurable (default: 6 pods with 2 CPU, 8GB RAM each)
- **ZooKeeper**: 3 replicas with 500m CPU, 1GB RAM each
- **Monitoring**: Prometheus + Grafana with persistent storage
- **Storage**: Persistent volumes + GCS backups

### Reduce Costs

1. Use smaller node types:
   ```hcl
   node_pool_machine_type = "n2-standard-4"
   ```

2. Reduce replica count for dev/test:
   ```hcl
   clickhouse_replicas = 1
   clickhouse_shards   = 1
   ```

3. Use standard persistent disks:
   ```hcl
   clickhouse_storage_class = "pd-standard"
   ```

4. Reduce backup retention:
   ```hcl
   backup_retention_days = 7
   ```

## Troubleshooting

### Check Cluster Status

```bash
kubectl get nodes
kubectl get pods -n clickhouse
kubectl get pods -n monitoring
```

### View Logs

```bash
# ClickHouse logs
kubectl logs -n clickhouse -l clickhouse.altinity.com/app=chop

# Operator logs
kubectl logs -n clickhouse -l app.kubernetes.io/name=clickhouse-operator

# ZooKeeper logs
kubectl logs -n clickhouse -l app.kubernetes.io/name=zookeeper
```

### Common Issues

#### Pods Stuck in Pending
- Check node resources: `kubectl describe node`
- Check PVC status: `kubectl get pvc -n clickhouse`

#### ClickHouse Not Starting
- Check logs: `kubectl logs -n clickhouse <pod-name>`
- Verify ZooKeeper connection: `kubectl logs -n clickhouse -l app.kubernetes.io/name=zookeeper`

#### Backup Failures
- Check backup pod logs: `kubectl logs -n clickhouse -l job-name=clickhouse-backup`
- Verify GCS permissions
- Check Workload Identity binding

### Debug Mode

Enable verbose logging:
```bash
kubectl set env -n clickhouse deployment/clickhouse-operator LOG_LEVEL=debug
```

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will delete:
- All ClickHouse data
- All persistent volumes
- GCS backup bucket (if empty)
- GKE cluster and all resources

Ensure you have backups before destroying!

## Repository Structure

```
.
├── terraform/              # Terraform deployment (GKE + ClickHouse)
│   ├── main.tf            # Root module
│   ├── variables.tf       # Input variables
│   ├── outputs.tf         # Output values
│   ├── providers.tf       # Provider configuration
│   └── modules/
│       ├── gke/          # GKE cluster module
│       ├── clickhouse/   # ClickHouse deployment module
│       ├── backup/       # Backup configuration module
│       └── monitoring/   # Monitoring stack module
│
├── kubernetes/            # Kubernetes YAML deployment
│   ├── base/             # Namespaces and storage classes
│   ├── clickhouse/       # ClickHouse cluster manifests
│   ├── zookeeper/        # ZooKeeper ensemble manifests
│   ├── backup/           # Backup CronJob and API
│   ├── monitoring/       # ServiceMonitor and alerts
│   ├── kustomization.yaml  # Root kustomization
│   └── DEPLOYMENT.md     # YAML deployment guide
│
└── README.md             # This file
```

## Support and Contributing

For issues, questions, or contributions:
1. Check existing documentation
2. Review Terraform plan output
3. Check pod logs for errors
4. Open an issue with detailed information

## License

[Your License Here]

## References

### ClickHouse
- [ClickHouse Documentation](https://clickhouse.com/docs)
- [ClickHouse Operator](https://github.com/Altinity/clickhouse-operator)
- [ClickHouse Backup Tool](https://github.com/AlexAkulov/clickhouse-backup)

### Kubernetes & GCP
- [GKE Documentation](https://cloud.google.com/kubernetes-engine/docs)
- [Kubernetes Documentation](https://kubernetes.io/docs)
- [Kustomize](https://kustomize.io/)

### Infrastructure as Code
- [Terraform GCP Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Terraform Kubernetes Provider](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs)
- [Helm Provider](https://registry.terraform.io/providers/hashicorp/helm/latest/docs)

### Monitoring
- [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator)
- [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
