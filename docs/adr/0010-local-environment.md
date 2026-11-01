# ADR-0010: Local = real Kubernetes (kind), not LocalStack

**Status:** Accepted

## Context
The task allows "AWS or a local stack that emulates it". The local environment should
let developers and reviewers test the things that actually break in production:
deploys, failover, network isolation, alerting.

## Decision
A **kind** cluster (3 nodes, labelled into 2 zones), provisioned **by Terraform** with the
same chart, Argo CD flow and observability module as AWS. AWS-only pieces have local
equivalents: Traefik for ALB, CloudNativePG for RDS, GHCR for ECR.

## Alternatives
- **LocalStack:** emulates AWS APIs, so Terraform for S3/IAM could be exercised. But EKS and
  RDS emulation is limited or paid, and it tests API calls rather than behaviour. You
  can't prove a failover or a NetworkPolicy against it.
- **minikube / k3d:** fine too. kind was chosen for multi-node clusters and zone labels in
  one config, and wide use in CI.
- **docker compose only:** kept as the fast inner loop (`make dev`), but it has no
  Kubernetes, so it can't validate the chart.

## Consequences
- + Every resilience claim in the docs was measured here (rolling deploys, DB failover, self-heal, alert firing).
- − AWS-specific Terraform (IAM, VPC, EKS) is validated and scanned but not exercised locally. Covered by dev on AWS when an account is available.
