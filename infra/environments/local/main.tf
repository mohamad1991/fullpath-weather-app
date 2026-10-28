# Local environment: a 3-node kind cluster that mirrors the AWS topology closely
# enough to test what matters - multi-"zone" scheduling, NetworkPolicy enforcement,
# restricted Pod Security, DB failover - for $0.
#
# AWS equivalents:  kind -> EKS | Traefik -> AWS LB Controller (ALB)
#                   CloudNativePG -> RDS Multi-AZ | CNPG secret -> External Secrets

resource "kind_cluster" "this" {
  name           = var.cluster_name
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role   = "control-plane"
      labels = { "ingress-ready" = "true" }
      extra_port_mappings {
        container_port = 80
        host_port      = var.ingress_host_port
        protocol       = "TCP"
      }
    }

    # Two workers labelled as different zones so topologySpreadConstraints and
    # CNPG anti-affinity behave like they would across AWS AZs.
    node {
      role   = "worker"
      labels = { "topology.kubernetes.io/zone" = "zone-a" }
    }
    node {
      role   = "worker"
      labels = { "topology.kubernetes.io/zone" = "zone-b" }
    }
  }
}

# --- Platform -------------------------------------------------------------------

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.chart_versions.metrics_server
  # kind kubelets use self-signed serving certs. Local only - never on EKS.
  values = [yamlencode({ args = ["--kubelet-insecure-tls"] })]
}

resource "helm_release" "traefik" {
  name             = "traefik"
  namespace        = "traefik"
  create_namespace = true
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = var.chart_versions.traefik
  wait             = true

  values = [yamlencode({
    ports        = { web = { hostPort = 80 } }
    service      = { spec = { type = "ClusterIP" } } # chart >=40 moved this under spec
    nodeSelector = { "ingress-ready" = "true" }
    tolerations  = [{ key = "node-role.kubernetes.io/control-plane", effect = "NoSchedule" }]
    ingressClass = { enabled = true, isDefaultClass = false }
  })]
}

resource "helm_release" "cnpg_operator" {
  name             = "cnpg"
  namespace        = "cnpg-system"
  create_namespace = true
  repository       = "https://cloudnative-pg.github.io/charts"
  chart            = "cloudnative-pg"
  version          = var.chart_versions.cnpg
  wait             = true
}

# --- Application namespace + database ------------------------------------------

resource "kubernetes_namespace_v1" "app" {
  metadata {
    name = var.app_namespace
    labels = {
      # Reject any pod that doesn't meet the "restricted" Pod Security Standard.
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}

resource "helm_release" "database" {
  name      = "weather-db"
  namespace = kubernetes_namespace_v1.app.metadata[0].name
  chart     = "${path.module}/../../charts/manifests"

  values = [yamlencode({
    manifests = [{
      apiVersion = "postgresql.cnpg.io/v1"
      kind       = "Cluster"
      metadata   = { name = "weather-db" }
      spec = {
        instances = var.db_instances
        storage   = { size = "1Gi" }
        bootstrap = { initdb = { database = "weather", owner = "weather" } }
        # Found in chaos testing: the default (180s) lets idle pooled client
        # connections hold a deleted primary in smart shutdown, delaying failover.
        smartShutdownTimeout = 15
      }
    }]
  })]

  depends_on = [helm_release.cnpg_operator]
}
