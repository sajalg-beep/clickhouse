# Create namespace for ClickHouse
resource "kubernetes_namespace" "clickhouse" {
  metadata {
    name = var.namespace
    labels = merge(
      var.labels,
      {
        name = var.namespace
      }
    )
  }
}

# Service Account for ClickHouse with Workload Identity
resource "kubernetes_service_account" "clickhouse" {
  metadata {
    name      = "clickhouse-sa"
    namespace = kubernetes_namespace.clickhouse.metadata[0].name
    annotations = var.enable_workload_identity ? {
      "iam.gke.io/gcp-service-account" = google_service_account.clickhouse[0].email
    } : {}
  }

  depends_on = [kubernetes_namespace.clickhouse]
}

# GCP Service Account for Workload Identity
resource "google_service_account" "clickhouse" {
  count        = var.enable_workload_identity ? 1 : 0
  account_id   = "${var.cluster_name}-clickhouse-sa"
  display_name = "ClickHouse Service Account"
  project      = var.project_id
}

# Workload Identity binding
resource "google_service_account_iam_member" "clickhouse_workload_identity" {
  count              = var.enable_workload_identity ? 1 : 0
  service_account_id = google_service_account.clickhouse[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/clickhouse-sa]"
}

# Install ClickHouse Operator using Helm
resource "helm_release" "clickhouse_operator" {
  name       = "clickhouse-operator"
  repository = "https://docs.altinity.com/clickhouse-operator/"
  chart      = "altinity-clickhouse-operator"
  version    = "0.23.5"
  namespace  = var.namespace

  create_namespace = false

  values = [
    yamlencode({
      operator = {
        image = {
          repository = "altinity/clickhouse-operator"
          tag        = "0.23.5"
        }
        resources = {
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
        }
      }
      metrics = {
        enabled = true
        image = {
          repository = "altinity/metrics-exporter"
          tag        = "0.23.5"
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.clickhouse]
}

# Deploy ZooKeeper ensemble for ClickHouse coordination
resource "helm_release" "zookeeper" {
  name       = "zookeeper"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "zookeeper"
  version    = "12.5.0"
  namespace  = var.namespace

  values = [
    yamlencode({
      replicaCount = 3

      persistence = {
        enabled      = true
        storageClass = var.storage_class
        size         = "10Gi"
      }

      resources = {
        limits = {
          cpu    = "1"
          memory = "2Gi"
        }
        requests = {
          cpu    = "500m"
          memory = "1Gi"
        }
      }

      metrics = {
        enabled = true
        serviceMonitor = {
          enabled = true
        }
      }

      affinity = {
        podAntiAffinity = {
          preferredDuringSchedulingIgnoredDuringExecution = [
            {
              weight = 100
              podAffinityTerm = {
                labelSelector = {
                  matchExpressions = [
                    {
                      key      = "app.kubernetes.io/name"
                      operator = "In"
                      values   = ["zookeeper"]
                    }
                  ]
                }
                topologyKey = "kubernetes.io/hostname"
              }
            }
          ]
        }
      }

      podLabels = var.labels
    })
  ]

  depends_on = [kubernetes_namespace.clickhouse]
}

# ClickHouse Installation manifest
resource "kubernetes_manifest" "clickhouse_installation" {
  manifest = {
    apiVersion = "clickhouse.altinity.com/v1"
    kind       = "ClickHouseInstallation"
    metadata = {
      name      = "clickhouse-cluster"
      namespace = var.namespace
      labels    = var.labels
    }
    spec = {
      defaults = {
        templates = {
          dataVolumeClaimTemplate = "data-volume"
          logVolumeClaimTemplate  = "log-volume"
          serviceTemplate         = "chi-service"
          podTemplate             = "clickhouse-pod"
        }
      }

      configuration = {
        users = {
          "admin/password" = "changeme"
          "admin/networks/ip" = ["::/0"]
          "admin/profile"     = "default"
          "admin/quota"       = "default"
        }

        profiles = {
          default = {
            max_memory_usage           = 10000000000
            use_uncompressed_cache     = 0
            load_balancing             = "random"
            log_queries                = 1
            log_query_threads          = 1
            max_execution_time         = 600
          }
        }

        quotas = {
          default = {
            interval = {
              duration      = 3600
              queries       = 0
              errors        = 0
              result_rows   = 0
              read_rows     = 0
              execution_time = 0
            }
          }
        }

        zookeeper = {
          nodes = [
            {
              host = "zookeeper-0.zookeeper-headless.${var.namespace}.svc.cluster.local"
              port = 2181
            },
            {
              host = "zookeeper-1.zookeeper-headless.${var.namespace}.svc.cluster.local"
              port = 2181
            },
            {
              host = "zookeeper-2.zookeeper-headless.${var.namespace}.svc.cluster.local"
              port = 2181
            }
          ]
        }

        clusters = [
          {
            name = "clickhouse-cluster"
            layout = {
              shardsCount   = var.shards
              replicasCount = var.replicas
            }
          }
        ]
      }

      templates = {
        podTemplates = [
          {
            name = "clickhouse-pod"
            spec = {
              serviceAccountName = kubernetes_service_account.clickhouse.metadata[0].name

              affinity = {
                podAntiAffinity = {
                  preferredDuringSchedulingIgnoredDuringExecution = [
                    {
                      weight = 100
                      podAffinityTerm = {
                        labelSelector = {
                          matchExpressions = [
                            {
                              key      = "clickhouse.altinity.com/app"
                              operator = "In"
                              values   = ["chop"]
                            }
                          ]
                        }
                        topologyKey = "kubernetes.io/hostname"
                      }
                    }
                  ]
                }
              }

              containers = [
                {
                  name  = "clickhouse"
                  image = "clickhouse/clickhouse-server:${var.version}"

                  ports = [
                    {
                      name          = "http"
                      containerPort = 8123
                    },
                    {
                      name          = "tcp"
                      containerPort = 9000
                    },
                    {
                      name          = "interserver"
                      containerPort = 9009
                    }
                  ]

                  resources = {
                    requests = {
                      cpu    = var.cpu
                      memory = var.memory
                    }
                    limits = {
                      cpu    = var.cpu
                      memory = var.memory
                    }
                  }

                  livenessProbe = {
                    httpGet = {
                      path = "/ping"
                      port = 8123
                    }
                    initialDelaySeconds = 60
                    periodSeconds       = 10
                    timeoutSeconds      = 5
                    failureThreshold    = 3
                  }

                  readinessProbe = {
                    httpGet = {
                      path = "/ping"
                      port = 8123
                    }
                    initialDelaySeconds = 30
                    periodSeconds       = 5
                    timeoutSeconds      = 3
                    failureThreshold    = 3
                  }

                  volumeMounts = [
                    {
                      name      = "data-volume"
                      mountPath = "/var/lib/clickhouse"
                    },
                    {
                      name      = "log-volume"
                      mountPath = "/var/log/clickhouse-server"
                    }
                  ]
                }
              ]
            }
          }
        ]

        volumeClaimTemplates = [
          {
            name = "data-volume"
            spec = {
              accessModes = ["ReadWriteOnce"]
              resources = {
                requests = {
                  storage = var.storage_size
                }
              }
              storageClassName = var.storage_class
            }
          },
          {
            name = "log-volume"
            spec = {
              accessModes = ["ReadWriteOnce"]
              resources = {
                requests = {
                  storage = "10Gi"
                }
              }
              storageClassName = var.storage_class
            }
          }
        ]

        serviceTemplates = [
          {
            name = "chi-service"
            spec = {
              ports = [
                {
                  name       = "http"
                  port       = 8123
                  targetPort = 8123
                },
                {
                  name       = "tcp"
                  port       = 9000
                  targetPort = 9000
                }
              ]
              type = "ClusterIP"
            }
          }
        ]
      }
    }
  }

  depends_on = [
    helm_release.clickhouse_operator,
    helm_release.zookeeper
  ]
}

# Service for external access (LoadBalancer)
resource "kubernetes_service" "clickhouse_lb" {
  metadata {
    name      = "clickhouse-lb"
    namespace = var.namespace
    labels    = var.labels
    annotations = {
      "cloud.google.com/load-balancer-type" = "Internal"
    }
  }

  spec {
    type = "LoadBalancer"

    selector = {
      "clickhouse.altinity.com/app" = "chop"
      "clickhouse.altinity.com/chi" = "clickhouse-cluster"
    }

    port {
      name        = "http"
      port        = 8123
      target_port = 8123
      protocol    = "TCP"
    }

    port {
      name        = "tcp"
      port        = 9000
      target_port = 9000
      protocol    = "TCP"
    }
  }

  depends_on = [kubernetes_manifest.clickhouse_installation]
}

# ConfigMap for custom ClickHouse configurations
resource "kubernetes_config_map" "clickhouse_config" {
  metadata {
    name      = "clickhouse-custom-config"
    namespace = var.namespace
  }

  data = {
    "custom.xml" = <<-EOT
      <?xml version="1.0"?>
      <clickhouse>
          <logger>
              <level>information</level>
              <log>/var/log/clickhouse-server/clickhouse-server.log</log>
              <errorlog>/var/log/clickhouse-server/clickhouse-server.err.log</errorlog>
              <size>1000M</size>
              <count>10</count>
          </logger>

          <query_log>
              <database>system</database>
              <table>query_log</table>
              <partition_by>toYYYYMM(event_date)</partition_by>
              <flush_interval_milliseconds>7500</flush_interval_milliseconds>
          </query_log>

          <max_connections>4096</max_connections>
          <max_concurrent_queries>100</max_concurrent_queries>

          <merge_tree>
              <parts_to_delay_insert>150</parts_to_delay_insert>
              <parts_to_throw_insert>300</parts_to_throw_insert>
              <max_parts_in_total>10000</max_parts_in_total>
          </merge_tree>
      </clickhouse>
    EOT
  }

  depends_on = [kubernetes_namespace.clickhouse]
}
