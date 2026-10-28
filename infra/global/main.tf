# Account-wide resources shared by all environments:
#   - ECR repositories: one image, built once, promoted dev -> prod by tag.
#   - GitHub Actions OIDC: CI assumes short-lived IAM roles, no static AWS keys anywhere.

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.70" }
  }
  backend "s3" {
    key          = "weather/global/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "eu-west-1"
}

variable "github_repository" {
  description = "owner/repo allowed to assume the CI roles."
  type        = string
}

variable "state_bucket" {
  type = string
}

locals {
  components = ["api", "collector", "frontend"]
  repo_sub   = "repo:${var.github_repository}"
}

data "aws_caller_identity" "current" {}

# --- ECR ------------------------------------------------------------------------------

resource "aws_ecr_repository" "this" {
  for_each = toset(local.components)

  name = "weather/${each.key}"
  # Immutable tags: a SHA tag can never be overwritten, so what was tested is what runs.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "KMS"
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 100 images (rollback window), expire older"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 100 }
      action       = { type = "expire" }
    }]
  })
}

# --- GitHub Actions OIDC ---------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

# Trust policy scoped by the token's "sub" claim: which repo AND which ref/event/environment.
data "aws_iam_policy_document" "trust" {
  for_each = {
    # Only main branch builds may push images.
    build = ["${local.repo_sub}:ref:refs/heads/main"]
    # Any PR may run a read-only plan.
    plan = ["${local.repo_sub}:pull_request", "${local.repo_sub}:ref:refs/heads/main"]
    # Apply only from jobs bound to a GitHub Environment (required reviewers on prod).
    apply = ["${local.repo_sub}:environment:dev", "${local.repo_sub}:environment:prod"]
  }

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = each.value
    }
  }
}

resource "aws_iam_role" "gha" {
  for_each             = data.aws_iam_policy_document.trust
  name                 = "gha-weather-${each.key}"
  assume_role_policy   = each.value.json
  max_session_duration = 3600
}

# build: push to the three ECR repos only.
resource "aws_iam_role_policy" "build" {
  role = aws_iam_role.gha["build"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = "ecr:GetAuthorizationToken", Resource = "*" },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart", "ecr:DescribeImages",
        ]
        Resource = [for r in aws_ecr_repository.this : r.arn]
      },
    ]
  })
}

# plan: read everything, write only the state lock file.
resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.gha["plan"].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "plan_state" {
  role = aws_iam_role.gha["plan"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:ListBucket"], Resource = "arn:aws:s3:::${var.state_bucket}" },
      { Effect = "Allow", Action = ["s3:GetObject"], Resource = "arn:aws:s3:::${var.state_bucket}/*" },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::${var.state_bucket}/*.tflock"
      },
      # Refresh of the non-sensitive db-connection secret (ReadOnlyAccess excludes GetSecretValue).
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:weather-*/db-connection-*"
      },
    ]
  })
}

# apply: broad by necessity (creates VPCs, IAM roles, EKS...). Mitigated by: OIDC
# subject pinned to GitHub Environments, required reviewers on prod, 1h sessions,
# CloudTrail. Next step: a permissions boundary on roles this role creates.
resource "aws_iam_role_policy_attachment" "apply_admin" {
  #checkov:skip=CKV_AWS_274:Apply role must create IAM/VPC/EKS; mitigated by OIDC env-scoped trust, prod reviewers, 1h sessions
  role       = aws_iam_role.gha["apply"].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

output "ecr_registry" {
  value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/weather"
}

output "role_arns" {
  value = { for k, r in aws_iam_role.gha : k => r.arn }
}
