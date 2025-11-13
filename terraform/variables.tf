variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
  default     = "clickhouse-cluster"
}

variable "zones" {
  description = "GCP zones for multi-zone deployment"
  type        = list(string)
  default     = ["us-central1-a", "us-central1-b", "us-central1-c"]
}

variable "clickhouse_namespace" {
  description = "Kubernetes namespace for ClickHouse"
  type        = string
  default     = "clickhouse"
}

variable "clickhouse_replicas" {
  description = "Number of ClickHouse replicas per shard"
  type        = number
  default     = 3
}

variable "clickhouse_shards" {
  description = "Number of ClickHouse shards"
  type        = number
  default     = 2
}

variable "clickhouse_version" {
  description = "ClickHouse version"
  type        = string
  default     = "23.8"
}

variable "clickhouse_cpu" {
  description = "CPU request for ClickHouse pods"
  type        = string
  default     = "2"
}

variable "clickhouse_memory" {
  description = "Memory request for ClickHouse pods"
  type        = string
  default     = "8Gi"
}

variable "clickhouse_storage_size" {
  description = "Storage size for each ClickHouse pod"
  type        = string
  default     = "100Gi"
}

variable "clickhouse_storage_class" {
  description = "Storage class for ClickHouse PVCs"
  type        = string
  default     = "pd-ssd"
}

variable "backup_enabled" {
  description = "Enable automated backups"
  type        = bool
  default     = true
}

variable "backup_schedule" {
  description = "Cron schedule for backups"
  type        = string
  default     = "0 2 * * *" # Daily at 2 AM
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
}

variable "backup_bucket_name" {
  description = "GCS bucket name for backups (will be created if not exists)"
  type        = string
  default     = ""
}

variable "monitoring_enabled" {
  description = "Enable Prometheus and Grafana monitoring"
  type        = bool
  default     = true
}

variable "enable_workload_identity" {
  description = "Enable Workload Identity for GKE"
  type        = bool
  default     = true
}

variable "network_name" {
  description = "VPC network name"
  type        = string
  default     = "clickhouse-network"
}

variable "subnet_name" {
  description = "Subnet name"
  type        = string
  default     = "clickhouse-subnet"
}

variable "subnet_cidr" {
  description = "Subnet CIDR"
  type        = string
  default     = "10.0.0.0/24"
}

variable "pods_cidr" {
  description = "CIDR for pods secondary IP range"
  type        = string
  default     = "10.1.0.0/16"
}

variable "services_cidr" {
  description = "CIDR for services secondary IP range"
  type        = string
  default     = "10.2.0.0/16"
}

variable "master_ipv4_cidr" {
  description = "CIDR for GKE master"
  type        = string
  default     = "172.16.0.0/28"
}

variable "node_pool_machine_type" {
  description = "Machine type for node pool"
  type        = string
  default     = "n2-standard-8"
}

variable "node_pool_disk_size_gb" {
  description = "Disk size for node pool"
  type        = number
  default     = 100
}

variable "node_pool_disk_type" {
  description = "Disk type for node pool"
  type        = string
  default     = "pd-ssd"
}

variable "node_pool_min_count" {
  description = "Minimum number of nodes per zone"
  type        = number
  default     = 1
}

variable "node_pool_max_count" {
  description = "Maximum number of nodes per zone"
  type        = number
  default     = 10
}

variable "maintenance_window_start" {
  description = "Maintenance window start time (HH:MM format, UTC)"
  type        = string
  default     = "03:00"
}

variable "maintenance_window_duration" {
  description = "Maintenance window duration in hours"
  type        = string
  default     = "4h"
}

variable "enable_binary_authorization" {
  description = "Enable Binary Authorization"
  type        = bool
  default     = false
}

variable "enable_network_policy" {
  description = "Enable network policy"
  type        = bool
  default     = true
}

variable "enable_pod_security_policy" {
  description = "Enable pod security policy"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    managed-by = "terraform"
    app        = "clickhouse"
  }
}
