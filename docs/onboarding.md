# Onboarding guide

For new developers and DevOps engineers on the team. Read [the architecture](architecture.md)
first; this page covers how to work here day to day.

## Day 1: get it running

```bash
# Prerequisites: Docker, Python 3.12, Node 22, gh (logged in), helm, kind
make venv          # .venv with hash-locked deps (+ .venv-tools for checkov)
make dev           # whole app in docker compose -> http://localhost:8080
make test          # lint + tests; API tests run against the real Postgres from compose
```

Then the full platform, the way it runs in the cloud:

```bash
export TF_VAR_github_token=$(gh auth token)   # never put tokens in files
make local-up       # kind + Traefik + CNPG + Argo CD + monitoring (~6 min)
open http://localhost:8088
kubectl -n argocd port-forward svc/argocd-server 8443:443                 # Argo CD UI
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3300:80   # Grafana
```

Grafana password: `terraform -chdir=infra/environments/local output -raw grafana_admin_password`.

## Developers: making a change

1. Branch, change code in `apps/<component>`, add or adjust tests in `apps/<component>/tests`.
2. `make test` locally, then open a PR. CI runs the same checks plus an image build and a vulnerability scan.
3. After merge, CI pushes the image and commits the new tag. Argo CD deploys it to dev and
   local within a few minutes. Watch it in the Argo CD UI.

**Rules of thumb**
- **Schema changes** go in a new numbered file in `apps/api/migrations/`. Never edit an
  applied migration. Make changes backward compatible: old pods keep running while new
  ones start (add a column, deploy, then use it, never rename in one step).
- **New dependency:** add it to `requirements.in` and run `make lock`. Never edit
  `requirements.txt` by hand (it holds hashes).
- **New endpoint:** keep it read-only and bounded (limits on ranges). Metrics come free
  via the middleware, keyed by the route template.
- **Logs:** app logs are JSON lines to stdout (uvicorn's own startup lines are plain text).
  Don't log secrets or full request bodies. Find logs in
  Grafana -> Explore -> Loki: `{namespace="weather", container="api"}`.

## DevOps: changing the platform

| I want to... | Change | It deploys via |
|---|---|---|
| Change replicas, resources, env vars, alerts | `deploy/charts/weather` or `deploy/environments/<env>/values.yaml` | Argo CD (on merge) |
| Promote a version to prod | Run the **Promote to prod** workflow -> review the PR | Argo CD (on merge) |
| Roll back | `git revert` the deploy commit | Argo CD |
| Change AWS infra or cluster add-ons | `infra/modules/*` | Terraform workflow: plan on PR, apply on merge |
| Add an alert | `deploy/charts/weather/rules/weather.rules.yaml` + test in `rules/tests/` + runbook in `docs/runbooks/` | Argo CD; CI enforces the test and runbook |

**Rules of thumb**
- **Never `kubectl apply/edit` in a shared environment.** Argo CD will undo it in seconds
  (self-heal). That's by design: Git is the source of truth. Use kubectl for reading
  and for incidents. If you must patch during an incident, commit the same change right after.
- **Read the plan.** Terraform PRs get a plan comment. Look for `destroy` and `replace`
  (`-/+`), especially on the database, the VPC or the cluster.
- **Pin everything:** chart versions, module versions, action SHAs. Renovate opens the upgrade PRs.
- **No secrets in Git, tfvars or CI logs.** Secrets live in AWS Secrets Manager and reach
  pods through External Secrets.
- Run `make lint-infra` and `make test-alerts` before pushing infra or alert changes.

## Debugging checklist

```bash
kubectl -n weather get pods,hpa,cronjob,ingress
kubectl -n weather describe pod <pod>           # Events at the bottom: probes, pulls, scheduling
kubectl -n weather logs <pod> [--previous]
kubectl -n argocd get applications              # OutOfSync / Degraded?
kubectl -n weather get externalsecret           # AWS: did secrets sync?
```

| Symptom | Usually |
|---|---|
| Pod `Running` but `0/1` ready | `/readyz` failing = the database can't be reached |
| `CreateContainerConfigError` | missing Secret / ConfigMap key |
| `ImagePullBackOff` | wrong tag or registry credentials |
| Works in compose, blocked in the cluster | NetworkPolicy: a new connection needs an explicit allow |
| My `kubectl edit` was reverted | Argo CD self-heal; change Git instead |

When an alert fires, open its `runbook_url` first. Every alert has one ([runbooks](runbooks/)).

## Where to go next
- [Decision records](adr/) explain *why* things are the way they are. Read them before
  proposing to change something big, and write a new ADR when you do.
