variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "vpc_cidr" {
  type = string
}

variable "single_nat_gateway" {
  type = bool
}

variable "kubernetes_version" {
  type = string
}

variable "api_allowed_cidrs" {
  type = list(string)
}

variable "admin_role_arns" {
  type    = map(string)
  default = {}
}

variable "viewer_role_arns" {
  type    = map(string)
  default = {}
}

variable "system_instance_types" {
  type = list(string)
}

variable "db_instance_class" {
  type = string
}

variable "db_multi_az" {
  type = bool
}

variable "db_backup_retention_days" {
  type = number
}

variable "db_deletion_protection" {
  type = bool
}

variable "bottlerocket_ami_alias" {
  type = string
}

variable "capacity_types" {
  type = list(string)
}

variable "karpenter_max_cpu" {
  type = number
}

variable "tags" {
  type    = map(string)
  default = {}
}
