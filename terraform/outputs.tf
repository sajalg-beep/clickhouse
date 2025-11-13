output "cluster_name" {
  description = "GKE cluster name"
  value       = module.gke.cluster_name
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = module.gke.cluster_endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "GKE cluster CA certificate"
  value       = module.gke.cluster_ca_certificate
  sensitive   = true
}

output "region" {
  description = "GCP region"
  value       = var.region
}

output "clickhouse_namespace" {
  description = "ClickHouse namespace (for K8s deployment)"
  value       = var.clickhouse_namespace
}

output "backup_bucket" {
  description = "GCS bucket for backups"
  value       = var.backup_enabled ? google_storage_bucket.clickhouse_backups[0].name : "N/A"
}

output "clickhouse_service_account" {
  description = "GCP Service Account for ClickHouse (Workload Identity)"
  value       = var.enable_workload_identity ? google_service_account.clickhouse[0].email : "N/A"
}

output "backup_service_account" {
  description = "GCP Service Account for Backup (Workload Identity)"
  value       = var.enable_workload_identity && var.backup_enabled ? google_service_account.clickhouse_backup[0].email : "N/A"
}

output "grafana_url" {
  description = "Grafana dashboard URL (port-forward required)"
  value       = var.monitoring_enabled ? "kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80" : "N/A"
}

output "connect_to_cluster" {
  description = "Command to configure kubectl"
  value       = "gcloud container clusters get-credentials ${module.gke.cluster_name} --region ${var.region} --project ${var.project_id}"
}

output "deploy_clickhouse" {
  description = "Command to deploy ClickHouse using K8s YAML"
  value       = "kubectl apply -k ../kubernetes/"
}

output "workload_identity_annotations" {
  description = "Annotations to add to Kubernetes ServiceAccounts"
  value = var.enable_workload_identity ? {
    clickhouse_sa = "iam.gke.io/gcp-service-account: ${google_service_account.clickhouse[0].email}"
    backup_sa     = var.backup_enabled ? "iam.gke.io/gcp-service-account: ${google_service_account.clickhouse_backup[0].email}" : "N/A"
  } : {}
}
