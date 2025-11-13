# Create monitoring namespace
resource "kubernetes_namespace" "monitoring" {
  count = var.enabled ? 1 : 0

  metadata {
    name = "monitoring"
    labels = merge(
      var.labels,
      {
        name = "monitoring"
      }
    )
  }
}

# Install Prometheus using Helm
resource "helm_release" "prometheus" {
  count = var.enabled ? 1 : 0

  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "55.5.0"
  namespace  = kubernetes_namespace.monitoring[0].metadata[0].name

  values = [
    yamlencode({
      prometheus = {
        prometheusSpec = {
          retention = "30d"

          resources = {
            requests = {
              cpu    = "500m"
              memory = "2Gi"
            }
            limits = {
              cpu    = "2"
              memory = "4Gi"
            }
          }

          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                accessModes = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "50Gi"
                  }
                }
                storageClassName = "pd-ssd"
              }
            }
          }

          # Service monitors for ClickHouse
          additionalScrapeConfigs = [
            {
              job_name = "clickhouse"
              kubernetes_sd_configs = [
                {
                  role = "pod"
                  namespaces = {
                    names = [var.clickhouse_namespace]
                  }
                }
              ]
              relabel_configs = [
                {
                  source_labels = ["__meta_kubernetes_pod_label_clickhouse_altinity_com_app"]
                  action        = "keep"
                  regex         = "chop"
                },
                {
                  source_labels = ["__meta_kubernetes_pod_container_port_number"]
                  action        = "keep"
                  regex         = "8123"
                },
                {
                  source_labels = ["__meta_kubernetes_pod_name"]
                  target_label  = "pod"
                },
                {
                  source_labels = ["__meta_kubernetes_namespace"]
                  target_label  = "namespace"
                }
              ]
              metrics_path = "/metrics"
            }
          ]
        }

        service = {
          type = "ClusterIP"
        }
      }

      grafana = {
        enabled = true

        adminPassword = "admin" # Change in production

        persistence = {
          enabled      = true
          storageClassName = "pd-standard"
          size         = "10Gi"
        }

        resources = {
          requests = {
            cpu    = "250m"
            memory = "512Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "1Gi"
          }
        }

        dashboardProviders = {
          "dashboardproviders.yaml" = {
            apiVersion = 1
            providers = [
              {
                name      = "default"
                orgId     = 1
                folder    = ""
                type      = "file"
                disableDeletion = false
                editable  = true
                options = {
                  path = "/var/lib/grafana/dashboards/default"
                }
              }
            ]
          }
        }

        dashboards = {
          default = {
            clickhouse-overview = {
              gnetId     = 882
              revision   = 1
              datasource = "Prometheus"
            }
            clickhouse-queries = {
              gnetId     = 14192
              revision   = 1
              datasource = "Prometheus"
            }
          }
        }

        service = {
          type = "ClusterIP"
        }
      }

      alertmanager = {
        enabled = true

        alertmanagerSpec = {
          storage = {
            volumeClaimTemplate = {
              spec = {
                accessModes = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "10Gi"
                  }
                }
                storageClassName = "pd-standard"
              }
            }
          }

          resources = {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }
        }

        config = {
          global = {
            resolve_timeout = "5m"
          }
          route = {
            group_by        = ["alertname", "cluster", "service"]
            group_wait      = "10s"
            group_interval  = "10s"
            repeat_interval = "12h"
            receiver        = "default"
          }
          receivers = [
            {
              name = "default"
              # Add your notification channels here (email, slack, etc.)
            }
          ]
        }
      }

      # Node exporter
      nodeExporter = {
        enabled = true
      }

      # Kube state metrics
      kubeStateMetrics = {
        enabled = true
      }
    })
  ]

  timeout = 600

  depends_on = [kubernetes_namespace.monitoring]
}

# PrometheusRule for ClickHouse alerts
resource "kubernetes_manifest" "clickhouse_alerts" {
  count = var.enabled ? 1 : 0

  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      name      = "clickhouse-alerts"
      namespace = kubernetes_namespace.monitoring[0].metadata[0].name
      labels    = var.labels
    }
    spec = {
      groups = [
        {
          name = "clickhouse"
          interval = "30s"
          rules = [
            {
              alert = "ClickHouseDown"
              expr  = "up{job=\"clickhouse\"} == 0"
              for   = "5m"
              labels = {
                severity = "critical"
              }
              annotations = {
                summary     = "ClickHouse instance is down"
                description = "ClickHouse instance {{ $labels.pod }} has been down for more than 5 minutes."
              }
            },
            {
              alert = "ClickHouseHighQueryDuration"
              expr  = "rate(clickhouse_query_duration_seconds_sum[5m]) / rate(clickhouse_query_duration_seconds_count[5m]) > 10"
              for   = "10m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary     = "ClickHouse queries are slow"
                description = "Average query duration on {{ $labels.pod }} is {{ $value }} seconds."
              }
            },
            {
              alert = "ClickHouseTooManyConnections"
              expr  = "clickhouse_metric_TCPConnection > 1000"
              for   = "5m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary     = "Too many TCP connections"
                description = "ClickHouse instance {{ $labels.pod }} has {{ $value }} TCP connections."
              }
            },
            {
              alert = "ClickHouseDiskSpaceHigh"
              expr  = "(clickhouse_metric_DiskDataBytes / clickhouse_metric_DiskAvailableBytes) > 0.8"
              for   = "10m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary     = "ClickHouse disk space usage is high"
                description = "Disk usage on {{ $labels.pod }} is above 80%."
              }
            },
            {
              alert = "ClickHouseReplicationLag"
              expr  = "clickhouse_metric_ReplicatedPartChecksFailed > 0"
              for   = "15m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary     = "ClickHouse replication issues"
                description = "Replication checks are failing on {{ $labels.pod }}."
              }
            },
            {
              alert = "ClickHouseZooKeeperDown"
              expr  = "clickhouse_metric_ZooKeeperSession == 0"
              for   = "5m"
              labels = {
                severity = "critical"
              }
              annotations = {
                summary     = "ClickHouse lost ZooKeeper connection"
                description = "ClickHouse instance {{ $labels.pod }} has no ZooKeeper session."
              }
            }
          ]
        }
      ]
    }
  }

  depends_on = [helm_release.prometheus]
}

# ServiceMonitor for ClickHouse metrics
resource "kubernetes_manifest" "clickhouse_service_monitor" {
  count = var.enabled ? 1 : 0

  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "clickhouse-metrics"
      namespace = var.clickhouse_namespace
      labels = merge(
        var.labels,
        {
          release = "prometheus"
        }
      )
    }
    spec = {
      selector = {
        matchLabels = {
          "clickhouse.altinity.com/app" = "chop"
        }
      }
      endpoints = [
        {
          port     = "http"
          path     = "/metrics"
          interval = "30s"
        }
      ]
    }
  }

  depends_on = [helm_release.prometheus]
}

# ConfigMap with custom Grafana dashboards
resource "kubernetes_config_map" "grafana_dashboards" {
  count = var.enabled ? 1 : 0

  metadata {
    name      = "clickhouse-dashboards"
    namespace = kubernetes_namespace.monitoring[0].metadata[0].name
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "clickhouse-custom.json" = jsonencode({
      title       = "ClickHouse Cluster Overview"
      uid         = "clickhouse-cluster-overview"
      description = "Custom ClickHouse cluster monitoring dashboard"
      panels = [
        {
          title = "Cluster Status"
          type  = "stat"
          gridPos = {
            x = 0
            y = 0
            w = 12
            h = 8
          }
          targets = [
            {
              expr = "up{job=\"clickhouse\"}"
            }
          ]
        },
        {
          title = "Query Rate"
          type  = "graph"
          gridPos = {
            x = 12
            y = 0
            w = 12
            h = 8
          }
          targets = [
            {
              expr = "rate(clickhouse_query_total[5m])"
            }
          ]
        }
      ]
    })
  }

  depends_on = [kubernetes_namespace.monitoring]
}
