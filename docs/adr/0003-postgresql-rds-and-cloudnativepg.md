# ADR-0003: PostgreSQL - RDS on AWS, CloudNativePG locally

**Status:** Accepted

## Context
The app stores weather history: relational, time-ordered, small, and mostly read. It
needs HA, backups and encryption, and the database is the one stateful part of the
system.

## Decision
- **AWS:** RDS for PostgreSQL. Multi-AZ, deletion protection and 14-day PITR in prod;
  single-AZ in dev. Encrypted with a customer-managed KMS key, `rds.force_ssl`, password
  generated and rotated by RDS in Secrets Manager.
- **Local:** CloudNativePG operator with a primary and a replica, so failover can actually
  be tested on a laptop.
- The app sees only host/port/user/password/sslmode, so it doesn't know or care which one
  it's using.

## Alternatives
- **Postgres in the cluster on AWS (CNPG on EKS):** cheaper and portable, but then we own
  backups, upgrades, storage and failover for the only data we can't recreate. Rejected
  for prod; a managed database is the right default for a small team.
- **Aurora PostgreSQL:** faster failover and storage auto-scaling, but costs more at this
  size. A good next step if read replicas or <30s failover become requirements.
- **DynamoDB / Timestream:** "latest per city" and time-range history are both simple SQL;
  no reason to give up relational queries.

## Consequences
- + Failover, backups and patching are AWS's job. Measured locally with CNPG: primary killed, ~31s to recover, 0 HTTP 500s.
- − Local and AWS differ (operator vs managed service). Mitigated: same engine major version, and the app is backend-agnostic.
- − DB alerts differ too: CNPG metrics locally, CloudWatch/RDS events on AWS.
