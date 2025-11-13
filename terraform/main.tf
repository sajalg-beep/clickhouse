# Random suffix for globally unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

# GKE Cluster Module - Infrastructure only
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

# GCS Bucket for ClickHouse Backups
resource "google_storage_bucket" "clickhouse_backups" {
  count    = var.backup_enabled ? 1 : 0
  name     = var.backup_bucket_name != "" ? var.backup_bucket_name : "${var.project_id}-clickhouse-backups-${random_id.suffix.hex}"
  location = var.region
  project  = var.project_id

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = var.backup_retention_days
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 3
    }
    action {
      type = "Delete"
    }
  }

  labels = var.labels
}

# Service Account for ClickHouse with Workload Identity
resource "google_service_account" "clickhouse" {
  count        = var.enable_workload_identity ? 1 : 0
  account_id   = "${var.cluster_name}-clickhouse-sa"
  display_name = "ClickHouse Workload Identity Service Account"
  project      = var.project_id
}

# Service Account for Backup with Workload Identity
resource "google_service_account" "clickhouse_backup" {
  count        = var.enable_workload_identity && var.backup_enabled ? 1 : 0
  account_id   = "${var.cluster_name}-backup-sa"
  display_name = "ClickHouse Backup Service Account"
  project      = var.project_id
}

# Grant backup service account access to GCS bucket
resource "google_storage_bucket_iam_member" "backup_writer" {
  count  = var.enable_workload_identity && var.backup_enabled ? 1 : 0
  bucket = google_storage_bucket.clickhouse_backups[0].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.clickhouse_backup[0].email}"
}

# Workload Identity binding for ClickHouse
resource "google_service_account_iam_member" "clickhouse_workload_identity" {
  count              = var.enable_workload_identity ? 1 : 0
  service_account_id = google_service_account.clickhouse[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.clickhouse_namespace}/clickhouse-sa]"
}

# Workload Identity binding for Backup
resource "google_service_account_iam_member" "backup_workload_identity" {
  count              = var.enable_workload_identity && var.backup_enabled ? 1 : 0
  service_account_id = google_service_account.clickhouse_backup[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.clickhouse_namespace}/clickhouse-backup-sa]"
}

# Monitoring Module (Prometheus Operator)
module "monitoring" {
  source = "./modules/monitoring"

  depends_on = [module.gke]

  enabled               = var.monitoring_enabled
  clickhouse_namespace  = var.clickhouse_namespace
  labels                = var.labels
}
