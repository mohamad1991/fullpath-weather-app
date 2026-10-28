variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "db_subnet_group" {
  type = string
}

variable "allowed_security_group_id" {
  description = "Security group allowed to connect on 5432 (EKS node SG)."
  type        = string
}

variable "engine_version" {
  type    = string
  default = "16"
}

variable "instance_class" {
  type = string
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "multi_az" {
  type = bool
}

variable "backup_retention_days" {
  type = number
}

variable "deletion_protection" {
  type = bool
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "monitoring_interval" {
  description = "Enhanced Monitoring interval in seconds (0 disables)."
  type        = number
  default     = 60
}
