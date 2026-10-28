# EKS control plane + a small managed "system" node group (runs Karpenter itself,
# CoreDNS and other add-ons). Application capacity is provisioned by Karpenter,
# which picks right-sized / spot instances per pending pod - better bin-packing
# and cost than fixed node groups + Cluster Autoscaler.

module "eks" {
  #checkov:skip=CKV_TF_1:Registry module pinned to an exact version; hashes are for git sources
  source  = "terraform-aws-modules/eks/aws"
  version = "21.29.0"

  name               = var.name
  kubernetes_version = var.kubernetes_version

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  # Public endpoint restricted to known CIDRs (office VPN / CI). Private endpoint
  # always on so nodes talk to the API server inside the VPC.
  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.api_allowed_cidrs
  endpoint_private_access      = true

  # Access entries (API mode) instead of the legacy aws-auth ConfigMap.
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true
  access_entries = merge(
    { for name, arn in var.admin_role_arns : name => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    } },
    # Read-only (incl. Secrets, which helm_release refresh needs) for the CI plan role.
    { for name, arn in var.viewer_role_arns : name => {
      principal_arn = arn
      policy_associations = {
        view = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminViewPolicy"
          access_scope = { type = "cluster" }
        }
      }
    } },
  )

  # Control plane audit logs -> CloudWatch (who did what to the cluster).
  enabled_log_types = ["api", "audit", "authenticator"]

  addons = {
    coredns                = {}
    kube-proxy             = {}
    eks-pod-identity-agent = { before_compute = true }
    vpc-cni = {
      before_compute = true
      # Without this, NetworkPolicies are accepted by the API but NOT enforced.
      configuration_values = jsonencode({ enableNetworkPolicy = "true" })
    }
    # EBS volumes for PVCs (Prometheus, Loki). Not installed by default on EKS: without
    # it every PVC stays Pending.
    aws-ebs-csi-driver = {
      pod_identity_association = [{
        role_arn        = module.ebs_csi_identity.iam_role_arn
        service_account = "ebs-csi-controller-sa"
      }]
    }
  }

  eks_managed_node_groups = {
    system = {
      # Bottlerocket: minimal, immutable, container-optimised OS - smaller attack surface.
      ami_type       = "BOTTLEROCKET_x86_64"
      instance_types = var.system_instance_types
      min_size       = 2
      max_size       = 3
      desired_size   = 2
      labels         = { "node-role" = "system" }
    }
  }

  node_security_group_tags = {
    "karpenter.sh/discovery" = var.name
  }

  tags = var.tags
}

# IAM role, SQS interruption queue (spot interruption / rebalance events) and
# Pod Identity association for the Karpenter controller.
module "karpenter" {
  #checkov:skip=CKV_TF_1:Registry module pinned to an exact version; hashes are for git sources
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.29.0"

  cluster_name = module.eks.cluster_name

  create_pod_identity_association = true
  namespace                       = "kube-system"
  service_account                 = "karpenter"

  node_iam_role_use_name_prefix = false
  node_iam_role_name            = "${var.name}-karpenter-node"
  node_iam_role_additional_policies = {
    # Shell access via SSM Session Manager instead of SSH keys / open port 22.
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = var.tags
}

module "ebs_csi_identity" {
  #checkov:skip=CKV_TF_1:Registry module pinned to an exact version; hashes are for git sources
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.10.0"

  name                      = "${var.name}-ebs-csi"
  attach_aws_ebs_csi_policy = true
  tags                      = var.tags
}
