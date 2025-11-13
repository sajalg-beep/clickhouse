output "namespace" {
  description = "ClickHouse namespace"
  value       = kubernetes_namespace.clickhouse.metadata[0].name
}

output "service_name" {
  description = "ClickHouse service name"
  value       = "clickhouse-cluster"
}

output "service_account_email" {
  description = "GCP service account email for ClickHouse"
  value       = var.enable_workload_identity ? google_service_account.clickhouse[0].email : ""
}

output "connection_info" {
  description = "ClickHouse connection information"
  value       = <<-EOT
    Internal HTTP endpoint: clickhouse-cluster.${kubernetes_namespace.clickhouse.metadata[0].name}.svc.cluster.local:8123
    Internal TCP endpoint: clickhouse-cluster.${kubernetes_namespace.clickhouse.metadata[0].name}.svc.cluster.local:9000

    To connect from within the cluster:
    clickhouse-client --host clickhouse-cluster.${kubernetes_namespace.clickhouse.metadata[0].name}.svc.cluster.local

    To connect from outside:
    kubectl port-forward -n ${kubernetes_namespace.clickhouse.metadata[0].name} svc/clickhouse-cluster 8123:8123 9000:9000
  EOT
}

output "operator_info" {
  description = "ClickHouse Operator information"
  value = {
    operator_version = "0.23.5"
    chart_version    = "0.23.5"
    namespace        = var.namespace
  }
}
