# dev: cost-optimised. Same architecture as prod, smaller and less redundant.
module "stack" {
  source = "../../modules/stack"

  environment        = "dev"
  vpc_cidr           = "10.10.0.0/16"
  kubernetes_version = "1.35" # check `aws eks describe-cluster-versions` before apply

  single_nat_gateway    = true # ~$65/mo saved per NAT; egress SPOF accepted in dev
  system_instance_types = ["t3.large"]
  capacity_types        = ["spot", "on-demand"]
  karpenter_max_cpu     = 16

  db_instance_class        = "db.t4g.micro"
  db_multi_az              = false # single-AZ; restore from snapshot if lost
  db_backup_retention_days = 3
  db_deletion_protection   = false

  bottlerocket_ami_alias = "bottlerocket@latest"
  api_allowed_cidrs      = var.api_allowed_cidrs
  admin_role_arns        = var.admin_role_arns
  viewer_role_arns       = var.viewer_role_arns
}
