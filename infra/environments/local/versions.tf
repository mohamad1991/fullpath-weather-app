terraform {
  required_version = ">= 1.10"

  required_providers {
    kind       = { source = "tehcyx/kind", version = "~> 0.13" }
    helm       = { source = "hashicorp/helm", version = "~> 3.3" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 3.4" }
  }

  # Local env = local state on purpose: it's a disposable dev cluster on a laptop.
  # AWS environments use the S3 backend (see environments/dev).
}

provider "kind" {}

provider "kubernetes" {
  host                   = kind_cluster.this.endpoint
  cluster_ca_certificate = kind_cluster.this.cluster_ca_certificate
  client_certificate     = kind_cluster.this.client_certificate
  client_key             = kind_cluster.this.client_key
}

provider "helm" {
  kubernetes = {
    host                   = kind_cluster.this.endpoint
    cluster_ca_certificate = kind_cluster.this.cluster_ca_certificate
    client_certificate     = kind_cluster.this.client_certificate
    client_key             = kind_cluster.this.client_key
  }
}
