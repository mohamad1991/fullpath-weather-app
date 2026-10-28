# WeatherCollectorFailing

**Meaning.** The most recent scheduled collector run did not succeed.

**Diagnose**
```bash
kubectl -n weather get jobs -l app.kubernetes.io/component=collector
kubectl -n weather logs job/<failed-job>
```
| Log says | Cause | Action |
|---|---|---|
| `fetch attempt N failed` ... HTTP 5xx/429 | Open-Meteo outage or rate limit | Wait; the next run retries. Check status of api.open-meteo.com |
| connection timeout to Open-Meteo | Egress blocked | NetworkPolicy `weather-collector-internet`, NAT gateway (AWS) |
| psycopg `OperationalError` | DB down / credentials | [WeatherDBInstanceDown](WeatherDBInstanceDown.md), Secret sync (ExternalSecret status) |
| `missing {...}` | Bad locations ConfigMap | Fix `collector.locations` in values, PR |

**Mitigate.** After fixing, run once by hand (see [WeatherDataStale](WeatherDataStale.md)).
Inserts are idempotent - re-running is always safe.
