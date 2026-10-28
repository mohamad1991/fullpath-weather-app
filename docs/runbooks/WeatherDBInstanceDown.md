# WeatherDBInstanceDown

**Meaning.** A Postgres instance (CloudNativePG, local) is not reporting, or fewer instances
than configured are up. On AWS the equivalent signals are RDS events / CloudWatch alarms.

**Diagnose**
```bash
kubectl -n weather get cluster weather-db            # phase, current primary
kubectl -n weather get pods -l cnpg.io/cluster=weather-db
kubectl -n weather logs <instance-pod> | tail -50
```
**Mitigate.** Primary lost -> CNPG promotes the replica automatically (~30s measured in
chaos testing); the API pool reconnects on its own. If the cluster is stuck, check PVCs
and node health. Never delete PVCs during an incident.
