# WeatherAPIUnavailable

**Meaning.** Zero ready `weather-api` pods for 2 minutes (or the Deployment is missing).
The API's own metrics can't report this - there's nothing running to count errors.

**Impact.** Total outage of the data API; the UI loads but shows no weather.

**Diagnose**
```bash
kubectl -n weather get pods -l app.kubernetes.io/component=api
kubectl -n weather describe pod <pod> | tail -20     # events: probes, image pulls, scheduling
kubectl -n weather logs <pod> --previous              # crash output
```
- `Running` but `0/1 READY` -> readiness (`/readyz`) failing = **database unreachable**.
  Check the DB (`WeatherDBInstanceDown`) and the `weather-db-app` / `weather-db` Secret.
- `ImagePullBackOff` -> bad tag or registry auth (check the last deploy commit).
- `CrashLoopBackOff` -> bad config or code: roll back.
- `Pending` -> no capacity: `kubectl get nodes`, Karpenter logs (AWS).

**Mitigate.** Roll back the last deploy (revert commit). If the DB is the cause, see
[WeatherDBInstanceDown](WeatherDBInstanceDown.md).
