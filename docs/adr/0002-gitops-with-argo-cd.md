# ADR-0002: GitOps with Argo CD (pull), not `helm upgrade` from CI (push)

**Status:** Accepted

## Context
Something has to apply the chart to the cluster on every change. Either CI pushes it
(`helm upgrade` with cluster credentials), or an in-cluster agent pulls the desired state
from Git.

## Decision
**Argo CD**, app-of-apps per environment, with auto-sync, `selfHeal` and `prune`. CI never
talks to the cluster: it builds and signs images, then commits the new tag to
`deploy/environments/<env>/values.yaml`. Prod changes by **PR only** (`promote.yml`
verifies cosign signatures and opens it; a code owner approves).

## Alternatives
- **Helm from GitHub Actions:** simple, but CI needs cluster-admin-ish credentials (a
  high-value secret outside the cluster), there's no drift detection, and "what's running"
  is only answerable by asking the cluster.
- **Flux:** equally valid. Argo CD was chosen for its UI, which helps junior engineers see
  sync and health state, and because it's more widely known.

## Consequences
- + Git is the audit log and the rollback button (`git revert`).
- + Drift is fixed automatically: a NetworkPolicy deleted by hand came back in ~2s.
- + No cluster credentials in CI.
- − One more critical component to run (HA on AWS). If it's down, deploys pause but running apps are unaffected.
- − Bot commits on `main` for tag bumps. The Deployment's `/spec/replicas` is ignored in Argo so it doesn't fight the HPA.
