# WeatherAPIAtMaxReplicas

**Meaning.** The API HPA has been at `maxReplicas` for 15 minutes - it wants more capacity
but isn't allowed to add it.

**Diagnose.** Is the load real (traffic up on the dashboard) or pathological (a client
hammering one route, a retry storm)? Check request rate by route.

**Mitigate.** Real load -> raise `api.autoscaling.maxReplicas` in the env values (PR);
Karpenter adds nodes. Abusive traffic -> rate-limit at the ALB/WAF. Check DB connections:
replicas x `DB_POOL_MAX` must stay below the DB's `max_connections`.
