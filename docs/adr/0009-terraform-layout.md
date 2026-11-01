# ADR-0009: Terraform layout - shared `stack` module per environment

**Status:** Accepted

## Context
dev and prod must have the same architecture at different sizes, with separate state
and blast radius. Some things exist once per account (state bucket, ECR, CI roles).

## Decision
```
infra/bootstrap        state bucket (local state, run once)
infra/global           ECR repos, GitHub OIDC provider + CI roles
infra/modules/stack    network + eks + database + platform-aws (+ observability)
infra/environments/dev|prod   ~20 lines each: call `stack` with sizing
infra/environments/local      kind + the same chart and observability module
```
- State in S3 with native locking (`use_lockfile`; no DynamoDB table needed any more).
- Community modules (vpc, eks, pod-identity) pinned to exact versions; provider lock files
  cover linux and macOS on both architectures.
- CRs (Karpenter NodePools, ClusterSecretStore, Argo CD Applications) are applied through a
  tiny local Helm chart (`infra/charts/manifests`) rather than `kubernetes_manifest`.
  The latter needs the CRDs to exist **at plan time**, which breaks a first-time apply.
- Pipeline: PRs get `plan` for dev and prod posted as a comment, plus Checkov. A merge
  applies dev, then prod applies **the saved, reviewed plan** after approval.

## Alternatives
- **Terragrunt:** DRYer across many environments and accounts. Not needed for two
  environments; adds a tool juniors would have to learn.
- **Workspaces:** one config for all environments, but easy to apply to the wrong one, and
  harder to see differences in review. Separate directories make the difference visible.
- **One state for everything:** a dev change could break prod at plan time; bigger blast radius.

## Consequences
- + Structural drift between dev and prod is impossible; only inputs differ.
- − Cluster add-ons are in Terraform while apps are in Argo CD: two tools. Deliberate: add-ons need IAM, which Terraform owns.
