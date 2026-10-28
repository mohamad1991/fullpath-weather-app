terraform {
  required_version = ">= 1.10"

  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 6.70" }
    helm       = { source = "hashicorp/helm", version = "~> 3.3" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 3.4" }
  }

  # State bucket from infra/bootstrap. use_lockfile = S3-native locking (TF >= 1.10),
  # no DynamoDB table. One state per environment: a bad dev apply can't touch prod.
  backend "s3" {
    key          = "weather/dev/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
    # bucket + region passed at init: terraform init -backend-config=../backend.hcl
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = { Repository = "fullpath-weather-app" }
  }
}

# Short-lived token via the AWS CLI on every run - no static kubeconfig/credentials.
provider "kubernetes" {
  host                   = module.stack.cluster_endpoint
  cluster_ca_certificate = base64decode(module.stack.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.stack.cluster_name, "--region", var.aws_region]
  }
}

provider "helm" {
  kubernetes = {
    host                   = module.stack.cluster_endpoint
    cluster_ca_certificate = base64decode(module.stack.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.stack.cluster_name, "--region", var.aws_region]
    }
  }
}
