variable "name" {
  type = string
}

variable "cluster_name" {
  description = "EKS cluster name, used for Karpenter subnet discovery tags."
  type        = string
}

variable "cidr" {
  type = string
}

variable "single_nat_gateway" {
  type = bool
}

variable "enable_flow_logs" {
  type    = bool
  default = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
