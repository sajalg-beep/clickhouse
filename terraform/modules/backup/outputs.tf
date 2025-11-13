output "bucket_name" {
  description = "GCS bucket name for backups"
  value       = var.enabled ? google_storage_bucket.backups[0].name : ""
}

output "bucket_url" {
  description = "GCS bucket URL"
  value       = var.enabled ? google_storage_bucket.backups[0].url : ""
}

output "service_account_email" {
  description = "Service account email for backups"
  value       = var.enabled && var.enable_workload_identity ? google_service_account.backup[0].email : ""
}

output "backup_schedule" {
  description = "Backup schedule"
  value       = var.schedule
}

output "backup_api_endpoint" {
  description = "Backup API endpoint (internal)"
  value       = var.enabled ? "clickhouse-backup-api.${var.namespace}.svc.cluster.local:7171" : ""
}
