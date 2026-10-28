# WeatherDataStale / WeatherDataStaleCritical

**Meaning.** The newest stored observation for a city is older than 1h (warning) or 3h
(critical). The collector normally writes every 15 minutes. This is the **silent failure**
mode: the API is healthy and returns 200s - with old data.

**Impact.** Users see outdated "current" weather.

**Diagnose**
```bash
kubectl -n weather get cronjob weather-collector          # SUSPEND? LAST SCHEDULE?
kubectl -n weather get jobs --sort-by=.metadata.creationTimestamp | tail -5
kubectl -n weather logs job/<latest-job>
```
- One city stale, others fresh -> location config/coordinates or provider gap for that point.
- All stale + jobs failing -> see [WeatherCollectorFailing](WeatherCollectorFailing.md).
- All stale + no jobs at all -> CronJob suspended, or the controller can't create pods
  (quota, Pod Security, image pull).

**Mitigate.** Fix the cause, then backfill immediately instead of waiting 15 min:
`kubectl -n weather create job --from=cronjob/weather-collector manual-$(date +%s)`
