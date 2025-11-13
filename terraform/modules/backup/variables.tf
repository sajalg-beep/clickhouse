variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "enabled" {
  description = "Enable backups"
  type        = bool
}

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
}

variable "schedule" {
  description = "Cron schedule for backups"
  type        = string
}

variable "retention_days" {
  description = "Number of days to retain backups"
  type        = number
}

variable "bucket_name" {
  description = "GCS bucket name for backups"
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
