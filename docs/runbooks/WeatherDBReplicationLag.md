# WeatherDBReplicationLag

**Meaning.** The replica is more than 30s behind the primary. If the primary failed now,
a failover would lose up to that much data.

**Diagnose.** Heavy write burst? Replica node under pressure (CPU/IO)? Network between zones?

**Mitigate.** Usually self-recovers after a burst. Persistent lag -> check replica resources
and storage IO; avoid planned switchovers until it's caught up.
