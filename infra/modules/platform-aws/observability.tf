# --- Observability on AWS --------------------------------------------------------------
# Same module as local (modules/observability); AWS adds durable storage:
#   Prometheus -> gp3 EBS PVCs, Loki -> S3 (via Pod Identity, no static keys).

locals {
  prod = var.environment == "prod"
}

# gp3: ~20% cheaper than gp2 with baseline IOPS independent of size. Encrypted at rest.
# WaitForFirstConsumer creates the volume in the AZ the pod is scheduled to - an EBS
# volume can't be attached across AZs.
resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name        = "gp3"
    annotations = { "storageclass.kubernetes.io/is-default-class" = "true" }
  }
  storage_provisioner    = "ebs.csi.aws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  reclaim_policy         = "Delete"
  parameters             = { type = "gp3", encrypted = "true" }
}

resource "aws_s3_bucket" "loki" {
  #checkov:skip=CKV_AWS_18:Access logging for a log-storage bucket only accessed by Loki adds cost, no audit value; CloudTrail covers API access
  #checkov:skip=CKV_AWS_144:Cross-region replication not justified for 14 days of operational logs
  #checkov:skip=CKV_AWS_145:SSE-S3 (AES256) is sufficient for app logs; no PII is logged
  #checkov:skip=CKV2_AWS_62:No consumers for bucket event notifications
  #checkov:skip=CKV_AWS_21:Versioning would keep chunks Loki's compactor deletes for retention; data is append-only
  bucket_prefix = "${var.cluster_name}-loki-"
  force_destroy = !local.prod
  tags          = var.tags
}

resource "aws_s3_bucket_public_access_block" "loki" {
  bucket                  = aws_s3_bucket.loki.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

# Loki's compactor enforces retention; the lifecycle rule is a backstop so a broken
# compactor can't grow the bill forever.
resource "aws_s3_bucket_lifecycle_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id
  rule {
    id     = "backstop-expiry"
    status = "Enabled"
    filter {}
    expiration { days = 30 }
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
  }
}

data "aws_iam_policy_document" "loki_s3" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.loki.arn]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.loki.arn}/*"]
  }
}

module "loki_identity" {
  #checkov:skip=CKV_TF_1:Registry module pinned to an exact version; hashes are for git sources
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.10.0"

  name                    = "${var.cluster_name}-loki"
  attach_custom_policy    = true
  source_policy_documents = [data.aws_iam_policy_document.loki_s3.json]

  associations = {
    this = {
      cluster_name    = var.cluster_name
      namespace       = "monitoring"
      service_account = "loki"
    }
  }
  tags = var.tags
}

module "observability" {
  source = "../observability"

  storage_class = kubernetes_storage_class_v1.gp3.metadata[0].name

  # prod: HA pairs (Alertmanager dedups; Grafana is stateless with sqlite per pod -
  # acceptable since dashboards are code). dev: single replicas, shorter retention.
  prometheus_replicas     = local.prod ? 2 : 1
  prometheus_retention    = local.prod ? "15d" : "7d"
  prometheus_storage_size = local.prod ? "50Gi" : "20Gi"
  alertmanager_replicas   = local.prod ? 2 : 1
  grafana_replicas        = 1
  loki_retention          = local.prod ? "336h" : "168h"
  loki_s3_bucket          = aws_s3_bucket.loki.id
  loki_s3_region          = data.aws_region.current.region
  slack_webhook_url       = var.slack_webhook_url

  depends_on = [helm_release.karpenter_nodepools, module.loki_identity]
}
