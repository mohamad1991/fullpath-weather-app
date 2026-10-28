terraform {
  required_version = ">= 1.10"
  required_providers {
    helm   = { source = "hashicorp/helm", version = "~> 3.3" }
    random = { source = "hashicorp/random", version = "~> 3.9" }
  }
}
