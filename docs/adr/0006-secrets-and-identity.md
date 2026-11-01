# ADR-0006: No static credentials - OIDC, Pod Identity, RDS-managed secrets

**Status:** Accepted

## Context
Three identities need AWS or database access: CI (build, plan, apply), in-cluster
controllers (Karpenter, LB controller, External Secrets, EBS CSI, Loki), and the app (DB
password). Long-lived keys leak through logs, laptops and forks.

## Decision
- **CI -> AWS:** GitHub OIDC with separate roles: `build` (push to ECR), `plan`
  (read-only, PRs), `apply` (only from `main` / the protected environment).
- **Pods -> AWS:** EKS **Pod Identity**, one role per controller, scoped to specific
  resources (e.g. External Secrets can read exactly the two app secrets and the deploy key).
- **DB password:** created and rotated by RDS (`manage_master_user_password`), stored in
  Secrets Manager under KMS, synced by **External Secrets** into a Kubernetes Secret.
  It never passes through Terraform variables or Git.
- **Argo CD -> GitHub:** read-only deploy key from Secrets Manager.

## Alternatives
- **IRSA:** works, but needs an OIDC provider and a trust policy per cluster. Pod Identity is simpler and is AWS's current recommendation.
- **Sealed Secrets / SOPS in Git:** encrypted secrets in Git work, but rotation means a commit, and the decryption key becomes the high-value secret.
- **Secrets Store CSI driver:** mounts secrets as files; fine, but env-var-based apps and rotation into Kubernetes Secrets are simpler with ESO.

## Consequences
- + Nothing to rotate by hand and nothing to leak in the repo or CI. Checkov passes with no secret findings.
- − Bootstrap order matters: ESO and its Pod Identity must exist before the app syncs. Terraform encodes this with `depends_on`.
- − The app reads the password once at startup, so a rotation needs a rolling restart. Next step: ESO refresh plus Reloader, or IAM database auth (already enabled on RDS).
