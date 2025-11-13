# Random suffix for globally unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

# GKE Cluster Module
module "gke" {
  source = "./modules/gke"

  project_id                   = var.project_id
  region                       = var.region
  zones                        = var.zones
  cluster_name                 = var.cluster_name
  network_name                 = var.network_name
  subnet_name                  = var.subnet_name
  subnet_cidr                  = var.subnet_cidr
  pods_cidr                    = var.pods_cidr
  services_cidr                = var.services_cidr
  master_ipv4_cidr             = var.master_ipv4_cidr
  node_pool_machine_type       = var.node_pool_machine_type
  node_pool_disk_size_gb       = var.node_pool_disk_size_gb
  node_pool_disk_type          = var.node_pool_disk_type
  node_pool_min_count          = var.node_pool_min_count
  node_pool_max_count          = var.node_pool_max_count
  enable_workload_identity     = var.enable_workload_identity
  enable_network_policy        = var.enable_network_policy
  enable_pod_security_policy   = var.enable_pod_security_policy
  enable_binary_authorization  = var.enable_binary_authorization
  maintenance_window_start     = var.maintenance_window_start
  maintenance_window_duration  = var.maintenance_window_duration
  labels                       = var.labels
}

# ClickHouse Module
module "clickhouse" {
  source = "./modules/clickhouse"

  depends_on = [module.gke]

  project_id           = var.project_id
  cluster_name         = var.cluster_name
  namespace            = var.clickhouse_namespace
  replicas             = var.clickhouse_replicas
  shards               = var.clickhouse_shards
  version              = var.clickhouse_version
  cpu                  = var.clickhouse_cpu
  memory               = var.clickhouse_memory
  storage_size         = var.clickhouse_storage_size
  storage_class        = var.clickhouse_storage_class
  enable_workload_identity = var.enable_workload_identity
  labels               = var.labels
}

# Backup Module
module "backup" {
  source = "./modules/backup"

  depends_on = [module.clickhouse]

  project_id            = var.project_id
  region                = var.region
  enabled               = var.backup_enabled
  namespace             = var.clickhouse_namespace
  schedule              = var.backup_schedule
  retention_days        = var.backup_retention_days
  bucket_name           = var.backup_bucket_name != "" ? var.backup_bucket_name : "${var.project_id}-clickhouse-backups-${random_id.suffix.hex}"
  enable_workload_identity = var.enable_workload_identity
  labels                = var.labels
}

# Monitoring Module
module "monitoring" {
  source = "./modules/monitoring"

  depends_on = [module.clickhouse]

  enabled               = var.monitoring_enabled
  clickhouse_namespace  = var.clickhouse_namespace
  labels                = var.labels
}
