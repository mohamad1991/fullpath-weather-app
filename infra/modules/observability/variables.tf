variable "storage_class" {
  description = "StorageClass for Prometheus/Loki volumes (kind: standard, EKS: gp3)."
  type        = string
}

variable "prometheus_replicas" {
  description = "2 on AWS: an HA pair, both scraping; Alertmanager dedups their alerts."
  type        = number
  default     = 1
}

variable "prometheus_retention" {
  type    = string
  default = "2d"
}

variable "prometheus_storage_size" {
  description = "PVC size per Prometheus replica. Empty = emptyDir (local only)."
  type        = string
  default     = ""
}

variable "alertmanager_replicas" {
  type    = number
  default = 1
}

variable "grafana_replicas" {
  type    = number
  default = 1
}

variable "loki_replicas" {
  type    = number
  default = 1
}

variable "loki_retention" {
  type    = string
  default = "168h"
}

variable "loki_s3_bucket" {
  description = "S3 bucket for Loki chunks/index. Empty = filesystem (local only)."
  type        = string
  default     = ""
}

variable "loki_s3_region" {
  type    = string
  default = ""
}

variable "slack_webhook_url" {
  description = "Slack incoming webhook for Alertmanager. Empty = alerts visible in Alertmanager UI only."
  type        = string
  default     = ""
  sensitive   = true
}

variable "chart_versions" {
  type = object({
    kube_prometheus_stack = string
    loki                  = string
    alloy                 = string
  })
  default = {
    kube_prometheus_stack = "92.14.1"
    loki                  = "7.5.0"
    alloy                 = "1.14.3"
  }
}
