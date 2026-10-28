# 3-AZ VPC with three subnet tiers:
#   public   - ALB + NAT gateways only. Nothing else gets a public IP.
#   private  - EKS nodes/pods. Egress via NAT.
#   database - RDS. No route to the internet at all.

data "aws_availability_zones" "available" {
  #checkov:skip=CKV_AWS_394:We slice the first 3 AZs; new AZs sort after them and do not change the selection
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

module "vpc" {
  #checkov:skip=CKV_TF_1:Registry module pinned to an exact version; hashes are for git sources
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.3"

  name = var.name
  cidr = var.cidr
  azs  = local.azs

  public_subnets   = [for i in range(3) : cidrsubnet(var.cidr, 8, i)]     # /24s: 10.x.0-2
  private_subnets  = [for i in range(3) : cidrsubnet(var.cidr, 4, i + 1)] # /20s: room for pod IPs (VPC CNI)
  database_subnets = [for i in range(3) : cidrsubnet(var.cidr, 8, i + 100)]

  create_database_subnet_group       = true
  create_database_subnet_route_table = true # isolated: no IGW/NAT route

  enable_nat_gateway = true
  # Cost vs HA: one NAT per AZ survives an AZ outage (prod); a single NAT saves
  # ~$65/month per gateway but is a SPOF for egress (dev).
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Flow logs: network forensics / audit evidence.
  enable_flow_log                                 = var.enable_flow_logs
  create_flow_log_cloudwatch_log_group            = var.enable_flow_logs
  create_flow_log_cloudwatch_iam_role             = var.enable_flow_logs
  flow_log_cloudwatch_log_group_retention_in_days = 30

  # Subnet discovery tags for the AWS Load Balancer Controller and Karpenter.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery"          = var.cluster_name
  }

  tags = var.tags
}
