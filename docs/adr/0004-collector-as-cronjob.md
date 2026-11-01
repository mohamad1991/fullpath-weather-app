# ADR-0004: Collector is a separate CronJob, not a thread in the API

**Status:** Accepted

## Context
Weather must be fetched from Open-Meteo periodically and stored. The simplest option
would be a background loop inside the API process.

## Decision
A separate image and a Kubernetes **CronJob** (`*/15 * * * *`, `concurrencyPolicy:
Forbid`). It makes one batched request for all cities, retries with backoff, and writes
with idempotent upserts (`ON CONFLICT DO NOTHING`).

## Alternatives
- **Thread inside the API:** with N replicas you get N fetches (or need leader election),
  and an external dependency's failures share a process with user traffic.
- **Long-running worker Deployment:** works, but holds resources 24/7 for a job that
  runs about 2 seconds every 15 minutes.
- **EventBridge + Lambda:** idiomatic serverless, but splits the system across two
  runtimes and wouldn't run on the local environment.

## Consequences
- + Exactly one run per schedule, whatever the API's scale. Separate NetworkPolicy: only the collector can reach the internet.
- + Idempotent, so a manual re-run (`kubectl create job --from=cronjob/...`) is always safe.
- − Failures are less visible than a crashing pod, so there's an explicit `WeatherCollectorFailing` alert plus the per-city `WeatherDataStale` alert.
