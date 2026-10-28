variable "cluster_name" {
  type    = string
  default = "weather"
}

variable "ingress_host_port" {
  description = "Host port mapped to the ingress controller (http://localhost:<port>)."
  type        = number
  default     = 8088
}

variable "app_namespace" {
  type    = string
  default = "weather"
}

variable "db_instances" {
  description = "CloudNativePG instances (1 primary + N-1 streaming replicas)."
  type        = number
  default     = 2
}

# Pinned chart versions. Bumped deliberately (Renovate PRs), never floating.
variable "chart_versions" {
  type = object({
    traefik        = string
    cnpg           = string
    metrics_server = string
  })
  default = {
    traefik        = "42.1.3"
    cnpg           = "0.29.1"
    metrics_server = "3.14.0"
  }
}
