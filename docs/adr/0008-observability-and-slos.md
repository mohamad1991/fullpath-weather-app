# ADR-0008: Prometheus/Grafana/Loki stack; SLO burn-rate alerting

**Status:** Accepted

## Context
We need to know that users are affected before they tell us, without paging people for
noise. The stack must run identically locally and on AWS.

## Decision
- **Stack:** kube-prometheus-stack (Prometheus, Alertmanager, Grafana, kube-state-metrics),
  Loki for logs, Grafana Alloy for collection (Promtail is deprecated). One Terraform
  module for all environments; AWS adds HA replicas, EBS volumes and S3 for Loki.
- **Ownership:** the platform owns the stack; the app chart ships its ServiceMonitor,
  PrometheusRule and dashboard, so they're versioned with the code they measure.
- **SLO-based alerting:** SLO 99.5% success on `/api/*` over 30 days. Multi-window burn-rate
  alerts (14.4x over 1h & 5m -> critical; 6x over 6h & 30m -> warning) instead of
  "error rate > X%".
- **Symptom alerts over cause alerts**, plus one data-quality signal: the age of the newest
  reading per city.
- **Alerts as tested code:** rules are plain Prometheus files, unit-tested with promtool in
  CI. CI also fails if any alert lacks a runbook or links to a missing one.

## Alternatives
- **CloudWatch Container Insights + CloudWatch Logs:** no stack to run, but per-metric and
  ingestion costs grow fast, PromQL-style SLO math is awkward, and it doesn't run locally.
  CloudWatch is still used for what only AWS can see (RDS events, control-plane logs).
- **Amazon Managed Prometheus + Managed Grafana:** a good move once more clusters exist;
  it removes Prometheus HA and storage ops. Today's PromQL, rules and dashboards carry over unchanged.
- **Datadog / New Relic:** fastest to value, but cost scales with hosts and volume; a business decision rather than a technical one.

## Consequences
- + The tests found real bugs. An error ratio with zero 5xx returned *no data* instead of 0,
  and `count()` over a fully-down database returned *nothing*, so `WeatherDBInstanceDown`
  never fired in an outage drill. Both are fixed with `or vector(0)`, and both have
  regression tests.
- − Prometheus/Loki capacity and upgrades are ours to run (see the AMP note above).
