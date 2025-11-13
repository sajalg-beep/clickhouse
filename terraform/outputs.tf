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
  description = "ClickHouse namespace"
  value       = var.clickhouse_namespace
}

output "clickhouse_service" {
  description = "ClickHouse service name"
  value       = module.clickhouse.service_name
}

output "clickhouse_connection_string" {
  description = "ClickHouse connection instructions"
  value       = module.clickhouse.connection_info
}

output "backup_bucket" {
  description = "GCS bucket for backups"
  value       = var.backup_enabled ? module.backup.bucket_name : "N/A"
}

output "grafana_url" {
  description = "Grafana dashboard URL (port-forward required)"
  value       = var.monitoring_enabled ? "kubectl port-forward -n monitoring svc/grafana 3000:80" : "N/A"
}

output "connect_to_cluster" {
  description = "Command to configure kubectl"
  value       = "gcloud container clusters get-credentials ${module.gke.cluster_name} --region ${var.region} --project ${var.project_id}"
}

output "clickhouse_operator_info" {
  description = "ClickHouse Operator information"
  value       = module.clickhouse.operator_info
}
