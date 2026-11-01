# ADR-0005: ALB on AWS, Traefik locally; Gateway API later

**Status:** Accepted

## Context
Traffic needs one entry point with path routing: `/api` to the API, everything else to
the frontend. ingress-nginx, long the default, was **retired in March 2026** and gets
no more fixes.

## Decision
- **AWS:** AWS Load Balancer Controller provisioning an ALB from the Ingress (TLS via ACM,
  WAF can be attached, IP target mode straight to pods).
- **Local:** Traefik as the controller, behind kind's port mapping on :8088.
- The chart uses a plain `Ingress` with `ingressClassName`, so only values change between
  environments.

## Alternatives
- **ingress-nginx:** retired, so starting on it now means planning a migration from day one.
- **Gateway API now:** the long-term direction (richer routing, role separation). Not
  chosen yet only to keep the chart simple. It's the planned next step, and both the AWS
  LB Controller and Traefik support it.
- **Service type LoadBalancer per service:** one NLB per service, no path routing, higher cost.

## Consequences
- + The managed ALB has no in-cluster proxy pods to scale or patch on AWS.
- − Local and AWS ingress behave slightly differently (timeouts, headers). Acceptable at this size.
- Lesson from setup: Traefik on kind needed `ingressEndpoint.hostname`, or Argo CD
  reports the Ingress as "Progressing" forever (no load-balancer address).
