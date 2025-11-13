output "prometheus_endpoint" {
  description = "Prometheus endpoint"
  value       = var.enabled ? "prometheus-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090" : ""
}

output "grafana_endpoint" {
  description = "Grafana endpoint"
  value       = var.enabled ? "prometheus-grafana.monitoring.svc.cluster.local:80" : ""
}

output "alertmanager_endpoint" {
  description = "Alertmanager endpoint"
  value       = var.enabled ? "prometheus-kube-prometheus-alertmanager.monitoring.svc.cluster.local:9093" : ""
}

output "grafana_admin_password" {
  description = "Grafana admin password (change this in production)"
  value       = var.enabled ? "admin" : ""
  sensitive   = true
}
