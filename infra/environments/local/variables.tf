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

# Pinned chart versions. Bumped deliberately via PR (read upstream release notes), never floating.
variable "chart_versions" {
  type = object({
    traefik        = string
    cnpg           = string
    metrics_server = string
    argocd         = string
  })
  default = {
    traefik        = "42.1.3"
    cnpg           = "0.29.1"
    metrics_server = "3.14.0"
    argocd         = "10.11.6"
  }
}

variable "github_repo_url" {
  type    = string
  default = "https://github.com/mohamad1991/fullpath-weather-app.git"
}

variable "github_username" {
  type    = string
  default = "mohamad1991"
}

# Token with repo + read:packages. Pass via env, never a file in Git:
#   export TF_VAR_github_token=$(gh auth token)
# Lands in local state (git-ignored, laptop only). On AWS, Argo CD uses a GitHub App
# / deploy key and nodes pull from ECR with IAM - no personal token involved.
variable "github_token" {
  type      = string
  sensitive = true
}
