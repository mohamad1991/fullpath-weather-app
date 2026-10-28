# WeatherAPIErrorBudgetBurnFast / WeatherAPIErrorBudgetBurnSlow

**Meaning.** The share of `/api/*` requests returning 5xx is consuming the 30-day error
budget (SLO 99.5%) faster than sustainable. *Fast* (14.4x for 1h, critical) = 2% of the
monthly budget per hour; at this rate the budget is gone in ~2 days. *Slow* (6x for 6h,
warning) = 5% of the budget per 6h.

**Impact.** Users see "Could not load weather" in the UI.

**Diagnose**
1. Dashboard row *RED*: which route, which status code? Started when?
2. Recent deploy? `kubectl -n argocd get application weather -o jsonpath='{.status.history[-1:]}'`
   and `git log -3 -- deploy/environments/`.
3. Errors in logs: Loki `{namespace="weather", container="api", level="ERROR"}`.
4. DB healthy? `kubectl -n weather get cluster weather-db` (local) / RDS console events (AWS).
   DB errors usually also fire `WeatherDBInstanceDown` or `WeatherDBPoolSaturated`.

**Mitigate**
- Started with a deploy -> **roll back**: revert the deploy commit
  (`git revert <sha>` on `deploy/environments/<env>/values.yaml`), Argo CD syncs within a minute.
  Rolling back first and debugging after is the default.
- DB failover in progress -> errors should clear within ~1 min of a new primary; watch.

**Follow-up.** Postmortem if > 10% of the monthly budget burned. Add a test/alert for the cause.
