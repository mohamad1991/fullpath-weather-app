output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value = module.eks.cluster_certificate_authority_data
}

# Values the GitOps environment file needs (deploy/environments/<env>/values.yaml).
output "helm_values" {
  description = "Paste into the env values file (or have CI render it)."
  value = {
    database = {
      externalSecret = {
        enabled    = true
        remoteKeys = [module.database.master_secret_arn, module.platform.db_connection_secret_name]
      }
    }
    networkPolicy = {
      ingressFromCIDRs = [module.network.vpc_cidr]
      databaseCIDRs    = module.network.database_subnet_cidrs
    }
  }
}
