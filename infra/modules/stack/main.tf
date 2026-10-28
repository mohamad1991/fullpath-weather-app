# One environment = network + EKS + database + platform add-ons.
# dev and prod call this with different sizing, so they cannot drift structurally.

locals {
  name = "weather-${var.environment}"
  tags = merge(var.tags, {
    Project     = "weather"
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

module "network" {
  source = "../network"

  name               = local.name
  cluster_name       = local.name
  cidr               = var.vpc_cidr
  single_nat_gateway = var.single_nat_gateway
  tags               = local.tags
}

module "eks" {
  source = "../eks"

  name                  = local.name
  kubernetes_version    = var.kubernetes_version
  vpc_id                = module.network.vpc_id
  private_subnet_ids    = module.network.private_subnet_ids
  api_allowed_cidrs     = var.api_allowed_cidrs
  admin_role_arns       = var.admin_role_arns
  viewer_role_arns      = var.viewer_role_arns
  system_instance_types = var.system_instance_types
  tags                  = local.tags
}

module "database" {
  source = "../database"

  name                      = local.name
  vpc_id                    = module.network.vpc_id
  db_subnet_group           = module.network.database_subnet_group
  allowed_security_group_id = module.eks.node_security_group_id
  instance_class            = var.db_instance_class
  multi_az                  = var.db_multi_az
  backup_retention_days     = var.db_backup_retention_days
  deletion_protection       = var.db_deletion_protection
  tags                      = local.tags
}

module "platform" {
  source = "../platform-aws"

  cluster_name             = module.eks.cluster_name
  vpc_id                   = module.network.vpc_id
  karpenter_queue_name     = module.eks.karpenter_queue_name
  karpenter_node_role_name = module.eks.karpenter_node_role_name
  bottlerocket_ami_alias   = var.bottlerocket_ami_alias
  capacity_types           = var.capacity_types
  max_cpu                  = var.karpenter_max_cpu
  db_address               = module.database.address
  db_port                  = module.database.port
  db_name                  = module.database.db_name
  db_master_secret_arn     = module.database.master_secret_arn
  db_kms_key_arn           = module.database.kms_key_arn
  tags                     = local.tags
}
