# prod: HA everywhere it matters - NAT per AZ, Multi-AZ RDS, deletion protection,
# pinned AMIs, on-demand baseline.
module "stack" {
  source = "../../modules/stack"

  environment        = "prod"
  vpc_cidr           = "10.20.0.0/16" # non-overlapping with dev: allows peering/TGW later
  kubernetes_version = "1.35"         # check `aws eks describe-cluster-versions` before apply

  single_nat_gateway    = false
  system_instance_types = ["m7i.large"]
  # Stateless pods tolerate spot (PDBs + 2-min interruption notice via SQS), but keep
  # on-demand allowed so capacity shortages never block scheduling.
  capacity_types    = ["spot", "on-demand"]
  karpenter_max_cpu = 64

  db_instance_class        = "db.m7g.large"
  db_multi_az              = true # synchronous standby in another AZ, ~60-120s failover
  db_backup_retention_days = 14   # + PITR
  db_deletion_protection   = true

  # AMI upgrades go through a PR in prod (test in dev with @latest first).
  bottlerocket_ami_alias = "bottlerocket@v1.40.0" # set to the version last validated in dev
  api_allowed_cidrs      = var.api_allowed_cidrs
  admin_role_arns        = var.admin_role_arns
  viewer_role_arns       = var.viewer_role_arns
}
