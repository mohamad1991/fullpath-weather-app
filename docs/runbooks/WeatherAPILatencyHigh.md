# WeatherAPILatencyHigh

**Meaning.** p95 latency of `/api/*` above 500ms for 10 minutes.

**Diagnose**
1. Dashboard: which route? Is the DB pool saturated (*Saturation* row)? CPU near request?
2. History queries over long ranges are the heaviest; check `hours=` in access patterns.
3. DB: slow-query log (`log_min_duration_statement=500ms` on RDS -> CloudWatch Logs).

**Mitigate.** CPU-bound -> HPA should be scaling; if at max see
[WeatherAPIAtMaxReplicas](WeatherAPIAtMaxReplicas.md). DB-bound -> see
[WeatherDBPoolSaturated](WeatherDBPoolSaturated.md).
