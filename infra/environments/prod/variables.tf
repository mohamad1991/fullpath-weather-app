variable "aws_region" {
  type    = string
  default = "eu-west-1"
}

variable "api_allowed_cidrs" {
  description = "Who may reach the EKS public API endpoint (office/VPN egress IPs, CI runners)."
  type        = list(string)
}

variable "admin_role_arns" {
  description = "IAM roles that get cluster-admin (e.g. SSO admin role, GitHub Actions apply role)."
  type        = map(string)
  default     = {}
}

variable "viewer_role_arns" {
  description = "IAM roles that get read-only cluster access (GitHub Actions plan role)."
  type        = map(string)
  default     = {}
}
