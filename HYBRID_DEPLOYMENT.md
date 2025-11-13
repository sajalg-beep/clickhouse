# Hybrid Deployment Guide (Recommended)

This is the **recommended deployment approach** that combines the best of both worlds:
- **Terraform**: Manages GKE infrastructure, networking, and GCP resources
- **Kubernetes YAML**: Deploys ClickHouse cluster with advanced scheduling features

## Why Hybrid Approach?

### Terraform for Infrastructure ✅
- Provision and manage GKE cluster
- Configure VPC networking and security
- Create GCS buckets for backups
- Set up Workload Identity service accounts
- Deploy monitoring stack (Prometheus Operator)
- Infrastructure as Code with state management

### Kubernetes YAML for ClickHouse ✅
- Fine-grained control over pod placement
- Topology spread constraints
- Rack awareness configuration
- Pod disruption budgets
- Easy to customize and iterate
- GitOps friendly
- Direct control over ClickHouse Operator CRDs

## Deployment Steps

### Phase 1: Infrastructure with Terraform

#### 1. Configure Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
project_id = "your-gcp-project-id"
region     = "us-central1"
zones      = ["us-central1-a", "us-central1-b", "us-central1-c"]

cluster_name = "clickhouse-cluster"

# Backup configuration
backup_enabled     = true
backup_bucket_name = ""  # Auto-generated if empty

# Monitoring
monitoring_enabled = true

# Security
enable_workload_identity = true
enable_network_policy    = true
```

#### 2. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review plan
terraform plan

# Apply configuration
terraform apply
```

**This creates:**
- Multi-zone GKE cluster with auto-scaling
- VPC network with private nodes
- GCS bucket for backups
- Service accounts with Workload Identity
- Prometheus Operator for monitoring
- All necessary IAM bindings

**Deployment time:** ~15 minutes

#### 3. Capture Terraform Outputs

```bash
# Get cluster credentials
terraform output connect_to_cluster
# Run the command shown

# Get service account emails for Workload Identity
terraform output clickhouse_service_account
terraform output backup_service_account

# Get backup bucket name
terraform output backup_bucket
```

### Phase 2: ClickHouse Deployment with Kubernetes YAML

#### 1. Install ClickHouse Operator

```bash
kubectl apply -f https://raw.githubusercontent.com/Altinity/clickhouse-operator/master/deploy/operator/clickhouse-operator-install-bundle.yaml
```

Verify operator is running:

```bash
kubectl get pods -n kube-system -l app=clickhouse-operator
```

#### 2. Configure Workload Identity

Update service account annotations with Terraform outputs:

```bash
# Get the service account emails from Terraform
CLICKHOUSE_SA=$(cd terraform && terraform output -raw clickhouse_service_account)
BACKUP_SA=$(cd terraform && terraform output -raw backup_service_account)
BACKUP_BUCKET=$(cd terraform && terraform output -raw backup_bucket)

echo "ClickHouse SA: $CLICKHOUSE_SA"
echo "Backup SA: $BACKUP_SA"
echo "Backup Bucket: $BACKUP_BUCKET"
```

Edit `kubernetes/clickhouse/service-account.yaml`:

```yaml
annotations:
  iam.gke.io/gcp-service-account: "YOUR_CLICKHOUSE_SA"
```

Edit `kubernetes/backup/service-account.yaml`:

```yaml
annotations:
  iam.gke.io/gcp-service-account: "YOUR_BACKUP_SA"
```

Edit `kubernetes/backup/configmap.yaml`:

```yaml
gcs:
  bucket: YOUR_BACKUP_BUCKET
```

#### 3. Label Nodes for Rack Awareness

See [NODE_LABELING.md](kubernetes/NODE_LABELING.md) for detailed instructions.

Quick automated labeling:

```bash
# Save this script
cat > label-nodes.sh <<'EOF'
#!/bin/bash
NODES=$(kubectl get nodes -o name)
RACK_NUM=1
for NODE in $NODES; do
  NODE_NAME=$(echo $NODE | cut -d'/' -f2)
  RACK="rack$RACK_NUM"
  echo "Labeling $NODE_NAME with rack=$RACK"
  kubectl label node $NODE_NAME topology.clickhouse.com/rack=$RACK --overwrite
  kubectl label node $NODE_NAME workload=clickhouse --overwrite
  RACK_NUM=$((RACK_NUM % 3 + 1))
done
EOF

chmod +x label-nodes.sh
./label-nodes.sh
```

Verify labels:

```bash
kubectl get nodes -o custom-columns=\
NAME:.metadata.name,\
ZONE:.metadata.labels."topology\.kubernetes\.io/zone",\
RACK:.metadata.labels."topology\.clickhouse\.com/rack"
```

#### 4. Deploy ClickHouse Cluster

```bash
# Deploy everything at once
kubectl apply -k kubernetes/

# Or deploy step by step
kubectl apply -k kubernetes/base/        # Namespaces & storage
kubectl apply -k kubernetes/zookeeper/   # ZooKeeper ensemble
sleep 30  # Wait for ZooKeeper to be ready
kubectl apply -k kubernetes/clickhouse/  # ClickHouse cluster
kubectl apply -k kubernetes/backup/      # Backup system
kubectl apply -k kubernetes/monitoring/  # Monitoring configs
```

**Deployment time:** ~10 minutes

#### 5. Verify Deployment

```bash
# Check all pods
kubectl get pods -n clickhouse -o wide

# Check ClickHouse installation
kubectl get clickhouseinstallation -n clickhouse

# Check services
kubectl get svc -n clickhouse

# Verify pod distribution across zones/racks
kubectl get pods -n clickhouse -o custom-columns=\
POD:.metadata.name,\
NODE:.spec.nodeName,\
ZONE:.spec.nodeSelector."topology\.kubernetes\.io/zone",\
STATUS:.status.phase
```

## Configuration Management

### Scaling ClickHouse

Edit `kubernetes/clickhouse/clickhouse-installation.yaml`:

```yaml
clusters:
  - name: clickhouse-cluster
    layout:
      shardsCount: 4      # Increase shards
      replicasCount: 3    # Increase replicas per shard
```

Apply changes:

```bash
kubectl apply -f kubernetes/clickhouse/clickhouse-installation.yaml
```

The operator will handle rolling updates automatically.

### Scaling Infrastructure

Edit `terraform/terraform.tfvars`:

```hcl
node_pool_max_count = 20  # Allow more nodes
```

Apply changes:

```bash
cd terraform
terraform apply
```

### Updating ClickHouse Version

Edit `kubernetes/clickhouse/clickhouse-installation.yaml`:

```yaml
containers:
  - name: clickhouse
    image: clickhouse/clickhouse-server:24.1  # New version
```

Apply:

```bash
kubectl apply -f kubernetes/clickhouse/clickhouse-installation.yaml
```

## Maintenance Operations

### Infrastructure Updates (Terraform)

```bash
cd terraform

# Update GKE version
terraform plan -target=module.gke
terraform apply -target=module.gke

# Update network configuration
terraform plan
terraform apply
```

### Application Updates (Kubernetes)

```bash
# Update ClickHouse configuration
kubectl edit clickhouseinstallation clickhouse-cluster -n clickhouse

# Update backup schedule
kubectl edit cronjob clickhouse-backup -n clickhouse

# Restart pods
kubectl rollout restart statefulset -n clickhouse
```

## Backup and Recovery

### Backups (Managed by CronJob)

Backups run automatically via CronJob. View status:

```bash
kubectl get cronjob -n clickhouse
kubectl get jobs -n clickhouse
```

### Manual Backup

```bash
# Port forward to backup API
kubectl port-forward -n clickhouse svc/clickhouse-backup-api 7171:7171 &

# Trigger backup
curl -X POST http://localhost:7171/backup/create

# List backups
curl http://localhost:7171/backup/list
```

### Restore

```bash
# List available backups in GCS
gsutil ls gs://$(cd terraform && terraform output -raw backup_bucket)/clickhouse-backups/

# Restore via backup API
kubectl exec -n clickhouse deployment/clickhouse-backup-api -- \
  clickhouse-backup restore backup-20240101-020000
```

## Monitoring

### Access Grafana

```bash
# Port forward (Grafana deployed by Terraform)
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Open http://localhost:3000
# Default credentials: admin/admin (change in production)
```

### View Metrics

```bash
# Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# ClickHouse metrics are automatically scraped via ServiceMonitor
```

## Advanced Features

### Pod Disruption Budgets

The deployment includes PDBs to ensure high availability:

```bash
# View PDBs
kubectl get pdb -n clickhouse

# ClickHouse PDB ensures minAvailable: 2 replicas per shard
```

### Topology Spread Constraints

Pods are automatically spread across:
- **Zones** (hard requirement): maxSkew=1
- **Racks** (soft preference): maxSkew=1
- **Nodes** (soft preference): maxSkew=1

Verify spread:

```bash
# Check pod distribution
kubectl get pods -n clickhouse -o wide

# Group by zone
kubectl get pods -n clickhouse -o json | \
  jq -r '.items[] | [.spec.nodeName, .metadata.name] | @tsv' | \
  while read node pod; do
    zone=$(kubectl get node $node -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}')
    rack=$(kubectl get node $node -o jsonpath='{.metadata.labels.topology\.clickhouse\.com/rack}')
    echo "$pod -> $node (zone: $zone, rack: $rack)"
  done
```

### Rack Awareness

Replicas are distributed across racks using node labels. See [NODE_LABELING.md](kubernetes/NODE_LABELING.md) for details.

## Troubleshooting

### Infrastructure Issues (Terraform)

```bash
cd terraform

# View current state
terraform show

# Refresh state
terraform refresh

# Fix drift
terraform plan
terraform apply
```

### Application Issues (Kubernetes)

```bash
# Check ClickHouse operator logs
kubectl logs -n kube-system -l app=clickhouse-operator --tail=100

# Check ClickHouse pod logs
kubectl logs -n clickhouse <pod-name> --tail=100

# Check events
kubectl get events -n clickhouse --sort-by='.lastTimestamp'

# Describe problematic pod
kubectl describe pod -n clickhouse <pod-name>
```

### Pods Not Scheduling

If pods can't schedule due to topology constraints:

```bash
# Check node resources
kubectl top nodes

# Check node labels
kubectl get nodes --show-labels

# Temporarily relax constraints by editing the ClickHouseInstallation
kubectl edit clickhouseinstallation clickhouse-cluster -n clickhouse

# Change whenUnsatisfiable: DoNotSchedule -> ScheduleAnyway
```

## Clean Up

### Delete ClickHouse Only (Keep Infrastructure)

```bash
kubectl delete -k kubernetes/
```

This removes ClickHouse but keeps:
- GKE cluster
- VPC network
- GCS backup bucket
- Service accounts
- Monitoring stack

### Delete Everything

```bash
# Delete ClickHouse first
kubectl delete -k kubernetes/

# Destroy infrastructure
cd terraform
terraform destroy
```

## Cost Optimization

### Development/Testing

For non-production:

**Terraform (`terraform.tfvars`):**
```hcl
node_pool_machine_type = "n2-standard-4"  # Smaller nodes
node_pool_min_count    = 1
node_pool_max_count    = 5
monitoring_enabled     = false            # Disable monitoring
```

**Kubernetes (`clickhouse-installation.yaml`):**
```yaml
shardsCount: 1
replicasCount: 2

resources:
  requests:
    cpu: "1"
    memory: "4Gi"
```

### Production

Use the default configuration for production-grade deployment.

## Best Practices

1. **Version Control**: Keep both Terraform and Kubernetes YAML in git
2. **Separate State**: Use different Terraform workspaces for dev/staging/prod
3. **Automated Testing**: Test configuration changes in dev before prod
4. **Backup Testing**: Regularly test restore procedures
5. **Monitoring**: Set up alerting in Prometheus/Alertmanager
6. **Security**: Rotate passwords regularly, enable audit logging
7. **Documentation**: Document any custom configurations
8. **GitOps**: Consider using ArgoCD or Flux for Kubernetes deployments

## Migration from Full Terraform

If you previously deployed with full Terraform (including ClickHouse module):

1. Export ClickHouse data:
   ```bash
   kubectl exec -n clickhouse <pod> -- clickhouse-backup create migration-backup
   kubectl exec -n clickhouse <pod> -- clickhouse-backup upload migration-backup
   ```

2. Remove ClickHouse from Terraform:
   ```bash
   terraform state rm module.clickhouse
   terraform state rm module.backup
   ```

3. Update `main.tf` to use new configuration (already done in this repo)

4. Apply Terraform changes:
   ```bash
   terraform apply
   ```

5. Deploy ClickHouse via YAML:
   ```bash
   kubectl apply -k kubernetes/
   ```

6. Restore data:
   ```bash
   kubectl exec -n clickhouse deployment/clickhouse-backup-api -- \
     clickhouse-backup restore migration-backup
   ```

## Next Steps

- [Node Labeling Guide](kubernetes/NODE_LABELING.md) - Configure rack awareness
- [Kubernetes YAML Deployment Guide](kubernetes/DEPLOYMENT.md) - Detailed K8s docs
- [Terraform Documentation](terraform/) - Infrastructure details

## Support

For issues:
1. Check Terraform output: `terraform output`
2. Check K8s resources: `kubectl get all -n clickhouse`
3. Check logs: Operator, ClickHouse pods, events
4. Review documentation in this repository
