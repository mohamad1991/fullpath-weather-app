# Weather App - platform reference implementation

Current weather for 8 cities around the world, with history over time. Small app, built
like a production service: Kubernetes, Terraform and GitHub Actions; GitOps with Argo CD;
security, HA, autoscaling, observability and cost decisions written down and tested.

```
Browser -> Ingress (ALB / Traefik) -> frontend (React, nginx)
                                   -> api (FastAPI) -> PostgreSQL (RDS Multi-AZ / CloudNativePG)
                       CronJob: collector -> Open-Meteo API -> PostgreSQL (every 15 min)
```

| | Local (runs on a laptop) | AWS (dev / prod) |
|---|---|---|
| Kubernetes | kind, 3 nodes in 2 "zones" | EKS + Karpenter, 3 AZs, Bottlerocket |
| Ingress | Traefik | AWS Load Balancer Controller (ALB) |
| Database | CloudNativePG, primary + replica | RDS PostgreSQL, Multi-AZ in prod |
| Secrets | Kubernetes Secret from the DB operator | Secrets Manager -> External Secrets (Pod Identity) |
| Images | GHCR | ECR (immutable tags) + GHCR |
| Deploys | Argo CD from this repo | Argo CD from this repo |
| Observability | Prometheus, Alertmanager, Grafana, Loki, Alloy | same module, HA + EBS/S3 storage |

The same Helm chart, the same Terraform modules and the same Argo CD flow run in both;
only sizing and the cloud-specific edges differ.

## Quick start

```bash
make dev                 # docker compose: app on http://localhost:8080 (fastest inner loop)

make local-up            # kind cluster + full platform via Terraform (needs Docker, ~6 min)
                         # Argo CD then deploys the app from Git: http://localhost:8088
make local-verify        # prove NetworkPolicies are actually enforced
make test test-alerts    # app tests (real Postgres) + alert rule unit tests
make lint-infra          # terraform fmt/validate, helm lint, Checkov
```

`make local-up` needs `TF_VAR_github_token=$(gh auth token)` (pulls the private images).
Pinned CLI versions (kubectl, terraform, promtool, actionlint) go in `.bin/`.

## Repository map

```
apps/              api (FastAPI), collector (CronJob), frontend (React)  - each with Dockerfile + tests
deploy/charts/     the Helm chart: workloads, HPA, PDB, NetworkPolicies, alerts, dashboard
deploy/environments/<env>/values.yaml   what runs where - CI bumps image tags here (GitOps)
deploy/argocd/     Argo CD Applications per environment
infra/bootstrap    S3 state bucket       infra/global   ECR + GitHub OIDC roles
infra/modules/     network, eks, database, platform-aws, observability, stack (= one env)
infra/environments/{local,dev,prod}
.github/workflows/ ci.yml (test/build/scan/sign/bump), terraform.yml (plan/apply), promote.yml
docs/              architecture, ADRs, runbooks, onboarding
```

## How a change reaches production

1. **PR** - CI runs lint, unit and integration tests (real Postgres), image build with a
   Trivy gate, chart lint plus schema validation for every environment, alert rule tests,
   and Terraform plan + Checkov. A code owner reviews.
2. **Merge** - images are pushed with the git SHA as tag, with SBOM and provenance, and signed
   with cosign (keyless). A bot commits the new tag to `deploy/environments/{dev,local}`.
3. **Argo CD** sees the commit and rolls it out (zero-downtime rolling update). About 4 minutes
   from merge to running.
4. **Prod** - `promote.yml` verifies the image signatures and opens a PR that bumps the
   prod tag. It deploys only after a code owner approves. Rollback = `git revert`.

## Documentation

- [Architecture](docs/architecture.md) - diagrams, request and data flows, HA and failure modes, cost
- [Decision records](docs/adr/) - why each major choice was made, and what was rejected
- [Onboarding guide](docs/onboarding.md) - for new developers and DevOps engineers on the team
- [Runbooks](docs/runbooks/) - one per alert

## What was verified, and what wasn't

Verified on the local environment (numbers from real runs):

| Test | Result |
|---|---|
| Rolling restart under load | 1,174 requests, 0 failures |
| Kill the Postgres primary | failover in ~31s, 0 HTTP 500s (2 client timeouts) |
| Delete a NetworkPolicy by hand | Argo CD restores it in ~2s |
| NetworkPolicy allow/deny matrix | 7/7 as expected |
| Full DB outage drill | `WeatherAPIUnavailable` reached Alertmanager at ~3.5 min, resolved ~2.5 min after recovery |
| Merge -> running on cluster | ~4 min, fully automated |
| Checkov (Terraform) | 0 failed; every skip has an inline reason |

**Not applied to a real AWS account** (no account or budget for this exercise). The AWS
Terraform is validated, scanned and plan-ready, and the AWS CI jobs switch on when
`AWS_ACCOUNT_ID` is set. Before a first apply, check the EKS version and the Bottlerocket
pin against what AWS offers that day.
