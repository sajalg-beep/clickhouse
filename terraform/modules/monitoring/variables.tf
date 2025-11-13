variable "enabled" {
  description = "Enable monitoring"
  type        = bool
}

variable "clickhouse_namespace" {
  description = "ClickHouse namespace to monitor"
  type        = string
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
}
