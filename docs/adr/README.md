# Architecture Decision Records

Short records of the decisions that shape this system. Each one gives the context, the
decision, the alternatives that were rejected, and the costs we accept. A new decision
that replaces an old one gets a new ADR and marks the old one *Superseded*. Old ADRs are
never edited to hide history.

| # | Decision | Status |
|---|---|---|
| [0001](0001-eks-as-the-platform.md) | EKS + Karpenter as the compute platform | Accepted |
| [0002](0002-gitops-with-argo-cd.md) | GitOps with Argo CD (pull), not `helm upgrade` from CI (push) | Accepted |
| [0003](0003-postgresql-rds-and-cloudnativepg.md) | PostgreSQL: RDS on AWS, CloudNativePG locally | Accepted |
| [0004](0004-collector-as-cronjob.md) | Collector is a separate CronJob, not a thread in the API | Accepted |
| [0005](0005-ingress.md) | ALB on AWS, Traefik locally; Gateway API later | Accepted |
| [0006](0006-secrets-and-identity.md) | No static credentials: OIDC, Pod Identity, RDS-managed secrets | Accepted |
| [0007](0007-supply-chain.md) | Supply chain: pinned, hash-locked, scanned, signed, immutable | Accepted |
| [0008](0008-observability-and-slos.md) | Prometheus/Grafana/Loki stack; SLO burn-rate alerting | Accepted |
| [0009](0009-terraform-layout.md) | Terraform layout: shared `stack` module per environment | Accepted |
| [0010](0010-local-environment.md) | Local = real Kubernetes (kind), not LocalStack | Accepted |
