# ADR-0007: Supply chain - pinned, hash-locked, scanned, signed, immutable

**Status:** Accepted

## Context
Most real incidents in this area come from dependencies, not our code: a moved Git tag
on a GitHub Action, a compromised PyPI release, a vulnerable base image.

## Decision
| Risk | Control |
|---|---|
| Malicious GitHub Action update | Every action pinned to a full commit SHA; Renovate proposes updates as PRs |
| Malicious / changed Python package | `pip-compile --generate-hashes` + `pip install --require-hashes` |
| Vulnerable image | Trivy gate on every build: fail on HIGH/CRITICAL that have a fix |
| "What exactly is running?" | Immutable git-SHA tags (no `latest`), ECR tag immutability, SBOM + SLSA provenance |
| Tampered image | cosign keyless signing in CI; `promote.yml` verifies signatures before opening the prod PR |
| Over-privileged CI | `permissions: contents: read` by default, write only per job when needed |

## Alternatives
- **Distroless images:** smaller still. Slim/Alpine was kept for debuggability; it's an easy follow-up.
- **Admission-time signature verification (Kyverno / sigstore policy-controller):** the
  right next step. Today verification happens at promotion, not at admission.

## Consequences
- + The Trivy gate already caught real issues: Starlette HIGH CVEs (fixed by upgrading FastAPI), and 58 CVEs in an old nginx/Alpine base (fixed by moving to nginx 1.30 / Alpine 3.24 and removing curl).
- − Upkeep: lock files and pins must be refreshed. Renovate automates the PRs.
