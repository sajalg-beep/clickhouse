# GCS Bucket for backups
resource "google_storage_bucket" "backups" {
  count    = var.enabled ? 1 : 0
  name     = var.bucket_name
  location = var.region
  project  = var.project_id

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = var.retention_days
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 3
    }
    action {
      type = "Delete"
    }
  }

  encryption {
    default_kms_key_name = ""
  }

  labels = var.labels
}

# Service Account for backup operations
resource "google_service_account" "backup" {
  count        = var.enabled && var.enable_workload_identity ? 1 : 0
  account_id   = "clickhouse-backup-sa"
  display_name = "ClickHouse Backup Service Account"
  project      = var.project_id
}

# Grant backup service account access to GCS bucket
resource "google_storage_bucket_iam_member" "backup_writer" {
  count  = var.enabled && var.enable_workload_identity ? 1 : 0
  bucket = google_storage_bucket.backups[0].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.backup[0].email}"
}

# Kubernetes Service Account for backup
resource "kubernetes_service_account" "backup" {
  count = var.enabled ? 1 : 0

  metadata {
    name      = "clickhouse-backup-sa"
    namespace = var.namespace
    annotations = var.enable_workload_identity ? {
      "iam.gke.io/gcp-service-account" = google_service_account.backup[0].email
    } : {}
  }
}

# Workload Identity binding for backup
resource "google_service_account_iam_member" "backup_workload_identity" {
  count              = var.enabled && var.enable_workload_identity ? 1 : 0
  service_account_id = google_service_account.backup[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/clickhouse-backup-sa]"
}

# ConfigMap for backup script
resource "kubernetes_config_map" "backup_script" {
  count = var.enabled ? 1 : 0

  metadata {
    name      = "clickhouse-backup-script"
    namespace = var.namespace
  }

  data = {
    "backup.sh" = <<-EOT
      #!/bin/bash
      set -e

      BACKUP_NAME="backup-$(date +%Y%m%d-%H%M%S)"
      BACKUP_PATH="/var/lib/clickhouse/backup/$BACKUP_NAME"
      GCS_BUCKET="${var.bucket_name}"

      echo "Starting backup: $BACKUP_NAME"

      # Create backup directory
      mkdir -p "$BACKUP_PATH"

      # Backup all databases using clickhouse-backup tool
      clickhouse-backup create "$BACKUP_NAME"

      # Upload to GCS
      clickhouse-backup upload "$BACKUP_NAME"

      echo "Backup completed: $BACKUP_NAME"

      # Clean old local backups (keep last 3)
      clickhouse-backup list local | tail -n +4 | xargs -I {} clickhouse-backup delete local {}

      # Clean old remote backups based on retention policy
      RETENTION_DATE=$(date -d "${var.retention_days} days ago" +%Y%m%d)
      clickhouse-backup list remote | grep -E "backup-[0-9]{8}" | awk -F'-' '{print $2}' | while read backup_date; do
        if [ "$backup_date" -lt "$RETENTION_DATE" ]; then
          clickhouse-backup delete remote "backup-$backup_date"
        fi
      done

      echo "Backup cleanup completed"
    EOT

    "restore.sh" = <<-EOT
      #!/bin/bash
      set -e

      if [ -z "$1" ]; then
        echo "Usage: $0 <backup-name>"
        echo "Available backups:"
        clickhouse-backup list remote
        exit 1
      fi

      BACKUP_NAME="$1"

      echo "Restoring backup: $BACKUP_NAME"

      # Download from GCS
      clickhouse-backup download "$BACKUP_NAME"

      # Restore
      clickhouse-backup restore "$BACKUP_NAME"

      echo "Restore completed: $BACKUP_NAME"
    EOT
  }
}

# ConfigMap for clickhouse-backup configuration
resource "kubernetes_config_map" "backup_config" {
  count = var.enabled ? 1 : 0

  metadata {
    name      = "clickhouse-backup-config"
    namespace = var.namespace
  }

  data = {
    "config.yml" = <<-EOT
      general:
        remote_storage: gcs
        disable_progress_bar: true
        backups_to_keep_local: 3
        backups_to_keep_remote: ${var.retention_days}

      clickhouse:
        username: admin
        password: changeme
        host: clickhouse-cluster
        port: 9000
        data_path: /var/lib/clickhouse
        skip_tables:
          - system.*
          - INFORMATION_SCHEMA.*
          - information_schema.*

      gcs:
        bucket: ${var.bucket_name}
        path: clickhouse-backups
        credentials_file: ""  # Use Workload Identity
        compression_level: 1
        compression_format: gzip

      api:
        listen: 0.0.0.0:7171
        enable_metrics: true
        enable_pprof: false
    EOT
  }
}

# CronJob for automated backups
resource "kubernetes_cron_job_v1" "backup" {
  count = var.enabled ? 1 : 0

  metadata {
    name      = "clickhouse-backup"
    namespace = var.namespace
    labels    = var.labels
  }

  spec {
    schedule                      = var.schedule
    timezone                      = "UTC"
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 3

    job_template {
      metadata {
        labels = var.labels
      }

      spec {
        template {
          metadata {
            labels = var.labels
          }

          spec {
            service_account_name = kubernetes_service_account.backup[0].metadata[0].name
            restart_policy       = "OnFailure"

            container {
              name  = "backup"
              image = "altinity/clickhouse-backup:2.4.34"

              command = ["/bin/sh", "-c"]
              args    = ["/scripts/backup.sh"]

              env {
                name  = "LOG_LEVEL"
                value = "info"
              }

              env {
                name  = "CLICKHOUSE_HOST"
                value = "clickhouse-cluster"
              }

              env {
                name  = "CLICKHOUSE_PORT"
                value = "9000"
              }

              env {
                name  = "CLICKHOUSE_USERNAME"
                value = "admin"
              }

              env {
                name  = "CLICKHOUSE_PASSWORD"
                value = "changeme"
              }

              volume_mount {
                name       = "backup-script"
                mount_path = "/scripts"
              }

              volume_mount {
                name       = "backup-config"
                mount_path = "/etc/clickhouse-backup"
              }

              resources {
                requests = {
                  cpu    = "500m"
                  memory = "1Gi"
                }
                limits = {
                  cpu    = "2"
                  memory = "4Gi"
                }
              }
            }

            volume {
              name = "backup-script"
              config_map {
                name         = kubernetes_config_map.backup_script[0].metadata[0].name
                default_mode = "0755"
              }
            }

            volume {
              name = "backup-config"
              config_map {
                name = kubernetes_config_map.backup_config[0].metadata[0].name
              }
            }
          }
        }
      }
    }
  }
}

# Deployment for backup API (for manual backups and restores)
resource "kubernetes_deployment" "backup_api" {
  count = var.enabled ? 1 : 0

  metadata {
    name      = "clickhouse-backup-api"
    namespace = var.namespace
    labels    = merge(var.labels, { app = "clickhouse-backup-api" })
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "clickhouse-backup-api"
      }
    }

    template {
      metadata {
        labels = merge(var.labels, { app = "clickhouse-backup-api" })
      }

      spec {
        service_account_name = kubernetes_service_account.backup[0].metadata[0].name

        container {
          name  = "backup-api"
          image = "altinity/clickhouse-backup:2.4.34"

          command = ["clickhouse-backup"]
          args    = ["server"]

          port {
            name           = "api"
            container_port = 7171
          }

          env {
            name  = "LOG_LEVEL"
            value = "info"
          }

          env {
            name  = "CLICKHOUSE_HOST"
            value = "clickhouse-cluster"
          }

          env {
            name  = "CLICKHOUSE_PORT"
            value = "9000"
          }

          volume_mount {
            name       = "backup-config"
            mount_path = "/etc/clickhouse-backup"
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 7171
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 7171
            }
            initial_delay_seconds = 10
            period_seconds        = 5
          }

          resources {
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

        volume {
          name = "backup-config"
          config_map {
            name = kubernetes_config_map.backup_config[0].metadata[0].name
          }
        }
      }
    }
  }
}

# Service for backup API
resource "kubernetes_service" "backup_api" {
  count = var.enabled ? 1 : 0

  metadata {
    name      = "clickhouse-backup-api"
    namespace = var.namespace
    labels    = var.labels
  }

  spec {
    selector = {
      app = "clickhouse-backup-api"
    }

    port {
      name        = "api"
      port        = 7171
      target_port = 7171
    }

    type = "ClusterIP"
  }
}
