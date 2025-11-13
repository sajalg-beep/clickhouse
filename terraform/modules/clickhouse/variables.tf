variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for ClickHouse"
  type        = string
}

variable "replicas" {
  description = "Number of ClickHouse replicas per shard"
  type        = number
}

variable "shards" {
  description = "Number of ClickHouse shards"
  type        = number
}

variable "version" {
  description = "ClickHouse version"
  type        = string
}

variable "cpu" {
  description = "CPU request for ClickHouse pods"
  type        = string
}

variable "memory" {
  description = "Memory request for ClickHouse pods"
  type        = string
}

variable "storage_size" {
  description = "Storage size for each ClickHouse pod"
  type        = string
}

variable "storage_class" {
  description = "Storage class for ClickHouse PVCs"
  type        = string
}

variable "enable_workload_identity" {
  description = "Enable Workload Identity"
  type        = bool
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
}
