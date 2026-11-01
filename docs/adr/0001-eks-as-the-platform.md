# ADR-0001: EKS + Karpenter as the compute platform

**Status:** Accepted

## Context
The task requires Kubernetes. On AWS that still leaves a choice: EKS with managed node
groups, EKS Auto Mode, or EKS with Karpenter. The app itself is small (3 workloads), but
the platform should look like what a team would run many services on.

## Decision
EKS with a small managed node group for system add-ons (Karpenter, CoreDNS, Argo CD) and
**Karpenter** for workload nodes. Bottlerocket on all nodes. Spot-first in both
environments, with on-demand allowed as a fallback.

## Alternatives
- **ECS Fargate:** cheaper and simpler for 3 services, and what I'd pick for a single small
  app with no platform ambitions. Rejected because Kubernetes is a hard requirement.
- **EKS Auto Mode:** less to operate (AWS runs Karpenter, CNI, storage), but costs extra
  per instance and gives less control over node configuration. A reasonable switch later
  if the team is small.
- **Cluster Autoscaler + node groups:** slower to react, limited to the instance types
  pre-defined in each group, and bin-packs worse than Karpenter.

## Consequences
- + Nodes appear within about a minute of pods going Pending; under-used nodes are consolidated; spot saves 60-70% on stateless pods.
- + Bottlerocket: minimal, immutable OS with a smaller attack surface; AMI pinned in prod and upgraded via PR.
- − Fixed costs (~$73/month control plane, NAT, system nodes) are big relative to this app. The platform pays off as more services share it.
- − The team has to understand Karpenter (NodePool limits, disruption budgets).
