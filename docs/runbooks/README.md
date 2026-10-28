# Runbooks

Every alert links here via its `runbook_url`. Same structure everywhere so on-call
never has to hunt: **Meaning → Impact → Diagnose → Mitigate → Follow-up**.

| Alert | Severity | Runbook |
|---|---|---|
| WeatherAPIErrorBudgetBurnFast / Slow | critical / warning | [WeatherAPIErrorBudgetBurn](WeatherAPIErrorBudgetBurn.md) |
| WeatherAPIUnavailable | critical | [WeatherAPIUnavailable](WeatherAPIUnavailable.md) |
| WeatherAPILatencyHigh | warning | [WeatherAPILatencyHigh](WeatherAPILatencyHigh.md) |
| WeatherDataStale / Critical | warning / critical | [WeatherDataStale](WeatherDataStale.md) |
| WeatherCollectorFailing | warning | [WeatherCollectorFailing](WeatherCollectorFailing.md) |
| WeatherAPIAtMaxReplicas | warning | [WeatherAPIAtMaxReplicas](WeatherAPIAtMaxReplicas.md) |
| WeatherDBPoolSaturated | warning | [WeatherDBPoolSaturated](WeatherDBPoolSaturated.md) |
| WeatherDBInstanceDown | critical | [WeatherDBInstanceDown](WeatherDBInstanceDown.md) |
| WeatherDBReplicationLag | warning | [WeatherDBReplicationLag](WeatherDBReplicationLag.md) |

Severity contract: **critical** = users are affected now, page (any hour).
**warning** = will become user-facing if ignored, handle in working hours.

Common first steps (all runbooks assume namespace `weather`):
```bash
kubectl -n weather get pods,hpa,cronjob
kubectl -n argocd get application weather          # was there a recent deploy?
git log --oneline -5 -- deploy/environments/        # what changed, when
```
Dashboard: Grafana -> "Weather - Service Overview". Logs: Grafana Explore -> Loki,
`{namespace="weather"}`.
