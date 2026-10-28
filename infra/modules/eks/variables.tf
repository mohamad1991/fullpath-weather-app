variable "name" {
  type = string
}

variable "kubernetes_version" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint."
  type        = list(string)
}

variable "admin_role_arns" {
  description = "IAM roles granted cluster-admin via EKS access entries (e.g. SSO admin role, CI apply role)."
  type        = map(string)
  default     = {}
}

variable "viewer_role_arns" {
  description = "IAM roles granted read-only cluster access (e.g. CI plan role)."
  type        = map(string)
  default     = {}
}

variable "system_instance_types" {
  type    = list(string)
  default = ["m7i.large"]
}

variable "tags" {
  type    = map(string)
  default = {}
}
