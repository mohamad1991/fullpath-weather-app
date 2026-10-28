variable "cluster_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "app_namespace" {
  type    = string
  default = "weather"
}

variable "karpenter_queue_name" {
  type = string
}

variable "karpenter_node_role_name" {
  type = string
}

variable "bottlerocket_ami_alias" {
  description = "Pin in prod (e.g. bottlerocket@v1.x.y) so AMI changes go through a PR; @latest in dev."
  type        = string
  default     = "bottlerocket@latest"
}

variable "capacity_types" {
  description = "Karpenter capacity types. Spot first is fine for stateless pods with PDBs."
  type        = list(string)
  default     = ["spot", "on-demand"]
}

variable "max_cpu" {
  description = "Upper bound on total vCPU Karpenter may provision."
  type        = number
  default     = 32
}

variable "db_address" {
  type = string
}

variable "db_port" {
  type = number
}

variable "db_name" {
  type = string
}

variable "db_master_secret_arn" {
  type = string
}

variable "db_kms_key_arn" {
  type = string
}

variable "chart_versions" {
  type = object({
    karpenter         = string
    aws_lb_controller = string
    external_secrets  = string
    metrics_server    = string
  })
  default = {
    karpenter         = "1.15.1"
    aws_lb_controller = "3.6.2"
    external_secrets  = "2.14.0"
    metrics_server    = "3.14.0"
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
