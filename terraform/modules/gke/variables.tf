variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "zones" {
  description = "GCP zones for multi-zone deployment"
  type        = list(string)
}

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
}

variable "network_name" {
  description = "VPC network name"
  type        = string
}

variable "subnet_name" {
  description = "Subnet name"
  type        = string
}

variable "subnet_cidr" {
  description = "Subnet CIDR"
  type        = string
}

variable "pods_cidr" {
  description = "CIDR for pods secondary IP range"
  type        = string
}

variable "services_cidr" {
  description = "CIDR for services secondary IP range"
  type        = string
}

variable "master_ipv4_cidr" {
  description = "CIDR for GKE master"
  type        = string
}

variable "node_pool_machine_type" {
  description = "Machine type for node pool"
  type        = string
}

variable "node_pool_disk_size_gb" {
  description = "Disk size for node pool"
  type        = number
}

variable "node_pool_disk_type" {
  description = "Disk type for node pool"
  type        = string
}

variable "node_pool_min_count" {
  description = "Minimum number of nodes per zone"
  type        = number
}

variable "node_pool_max_count" {
  description = "Maximum number of nodes per zone"
  type        = number
}

variable "enable_workload_identity" {
  description = "Enable Workload Identity"
  type        = bool
}

variable "enable_network_policy" {
  description = "Enable network policy"
  type        = bool
}

variable "enable_pod_security_policy" {
  description = "Enable pod security policy"
  type        = bool
}

variable "enable_binary_authorization" {
  description = "Enable Binary Authorization"
  type        = bool
}

variable "maintenance_window_start" {
  description = "Maintenance window start time (HH:MM format, UTC)"
  type        = string
}

variable "maintenance_window_duration" {
  description = "Maintenance window duration in hours"
  type        = string
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
}
