# Cluster add-ons that need AWS IAM wiring live here (Terraform owns IAM).
# Application workloads are NOT here - Argo CD deploys those from Git.

data "aws_region" "current" {}

locals {
  manifests_chart = "${path.module}/../../charts/manifests"
}

# --- Karpenter: node autoscaling ---------------------------------------------------

resource "helm_release" "karpenter" {
  name       = "karpenter"
  namespace  = "kube-system"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.chart_versions.karpenter
  wait       = true

  values = [yamlencode({
    replicas     = 2
    nodeSelector = { "node-role" = "system" } # must not run on nodes it manages
    settings = {
      clusterName       = var.cluster_name
      interruptionQueue = var.karpenter_queue_name
    }
    serviceAccount = { name = "karpenter" }
  })]
}

resource "helm_release" "karpenter_nodepools" {
  name      = "karpenter-nodepools"
  namespace = "kube-system"
  chart     = local.manifests_chart

  values = [yamlencode({
    manifests = [
      {
        apiVersion = "karpenter.k8s.aws/v1"
        kind       = "EC2NodeClass"
        metadata   = { name = "default" }
        spec = {
          role                       = var.karpenter_node_role_name
          amiSelectorTerms           = [{ alias = var.bottlerocket_ami_alias }]
          subnetSelectorTerms        = [{ tags = { "karpenter.sh/discovery" = var.cluster_name } }]
          securityGroupSelectorTerms = [{ tags = { "karpenter.sh/discovery" = var.cluster_name } }]
          # IMDSv2 only, hop limit 1: pods cannot reach the instance metadata service
          # to steal the node's IAM credentials. Pods get AWS creds via Pod Identity.
          metadataOptions = { httpTokens = "required", httpPutResponseHopLimit = 1 }
        }
      },
      {
        apiVersion = "karpenter.sh/v1"
        kind       = "NodePool"
        metadata   = { name = "default" }
        spec = {
          template = {
            spec = {
              nodeClassRef = { group = "karpenter.k8s.aws", kind = "EC2NodeClass", name = "default" }
              requirements = [
                { key = "karpenter.sh/capacity-type", operator = "In", values = var.capacity_types },
                { key = "kubernetes.io/arch", operator = "In", values = ["amd64"] },
                { key = "karpenter.k8s.aws/instance-category", operator = "In", values = ["c", "m", "r"] },
                { key = "karpenter.k8s.aws/instance-generation", operator = "Gt", values = ["5"] },
              ]
              expireAfter = "720h" # recycle nodes monthly: picks up patched AMIs
            }
          }
          limits = { cpu = var.max_cpu } # cost guardrail against runaway scaling
          disruption = {
            consolidationPolicy = "WhenEmptyOrUnderutilized"
            consolidateAfter    = "1m"
          }
        }
      },
    ]
  })]

  depends_on = [helm_release.karpenter]
}

# --- AWS Load Balancer Controller: Ingress -> ALB ------------------------------------

module "lb_controller_identity" {
  #checkov:skip=CKV_TF_1:Registry module pinned to an exact version; hashes are for git sources
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.10.0"

  name                            = "${var.cluster_name}-aws-lbc"
  attach_aws_lb_controller_policy = true

  associations = {
    this = {
      cluster_name    = var.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }
  tags = var.tags
}

resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.chart_versions.aws_lb_controller
  wait       = true

  values = [yamlencode({
    clusterName    = var.cluster_name
    region         = data.aws_region.current.region
    vpcId          = var.vpc_id
    replicaCount   = 2
    serviceAccount = { name = "aws-load-balancer-controller" }
  })]

  depends_on = [module.lb_controller_identity, helm_release.karpenter_nodepools]
}

# --- External Secrets: AWS Secrets Manager -> k8s Secret ----------------------------

# Non-secret connection details, stored next to the RDS-managed credentials so the
# ExternalSecret can merge both into the {host,port,dbname,username,password} contract.
resource "aws_secretsmanager_secret" "db_connection" {
  #checkov:skip=CKV2_AWS_57:Holds host/port/dbname only - nothing secret to rotate (credentials rotate in the RDS secret)
  name                    = "${var.cluster_name}/db-connection"
  kms_key_id              = var.db_kms_key_arn
  description             = "RDS endpoint for the weather app (non-sensitive; credentials live in the RDS-managed secret)"
  recovery_window_in_days = 0
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "db_connection" {
  secret_id = aws_secretsmanager_secret.db_connection.id
  secret_string = jsonencode({
    host   = var.db_address
    port   = tostring(var.db_port)
    dbname = var.db_name
  })
}

module "external_secrets_identity" {
  #checkov:skip=CKV_TF_1:Registry module pinned to an exact version; hashes are for git sources
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.10.0"

  name                           = "${var.cluster_name}-external-secrets"
  attach_external_secrets_policy = true
  # Least privilege: only the two secrets this app needs, read-only.
  external_secrets_secrets_manager_arns = [var.db_master_secret_arn, aws_secretsmanager_secret.db_connection.arn]
  external_secrets_kms_key_arns         = [var.db_kms_key_arn]
  external_secrets_create_permission    = false

  associations = {
    this = {
      cluster_name    = var.cluster_name
      namespace       = "external-secrets"
      service_account = "external-secrets"
    }
  }
  tags = var.tags
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.chart_versions.external_secrets
  wait             = true

  values = [yamlencode({
    serviceAccount = { name = "external-secrets" }
  })]

  depends_on = [module.external_secrets_identity, helm_release.karpenter_nodepools]
}

resource "helm_release" "secret_store" {
  name      = "secret-store"
  namespace = "external-secrets"
  chart     = local.manifests_chart

  values = [yamlencode({
    manifests = [{
      apiVersion = "external-secrets.io/v1"
      kind       = "ClusterSecretStore"
      metadata   = { name = "aws-secrets-manager" }
      spec = {
        provider = {
          aws = { service = "SecretsManager", region = data.aws_region.current.region }
        }
        # Restrict which namespaces may use this store.
        conditions = [{ namespaces = [var.app_namespace] }]
      }
    }]
  })]

  depends_on = [helm_release.external_secrets]
}

# --- metrics-server: feeds HPA ----------------------------------------------------

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.chart_versions.metrics_server
  values     = [yamlencode({ replicas = 2 })]
  depends_on = [helm_release.karpenter_nodepools]
}

# --- Application namespace ------------------------------------------------------------

resource "kubernetes_namespace_v1" "app" {
  metadata {
    name = var.app_namespace
    labels = {
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}
