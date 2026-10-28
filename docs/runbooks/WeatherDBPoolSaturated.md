# WeatherDBPoolSaturated

**Meaning.** Requests on an API pod are queueing for a DB connection - all `DB_POOL_MAX`
connections are busy.

**Diagnose.** Slow queries (DB CPU, slow-query log) vs. genuinely more concurrency.
Dashboard *Saturation* row: in-use vs max per pod.

**Mitigate.** Slow DB -> fix the query/index, scale the DB instance class. More concurrency
-> more API replicas (each brings its own pool) rather than a bigger pool per pod; keep
`replicas x DB_POOL_MAX < max_connections` (consider RDS Proxy at larger scale).
