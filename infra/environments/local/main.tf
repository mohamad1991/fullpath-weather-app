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
    ports = { web = { hostPort = 80 } }
    # hostPort + one ingress node: a surge pod can never schedule (port taken by the
    # old pod) and the rollout deadlocks. Replace in place instead (brief local blip).
    updateStrategy = { type = "RollingUpdate", rollingUpdate = { maxSurge = 0, maxUnavailable = 1 } }
    service        = { spec = { type = "ClusterIP" } } # chart >=40 moved this under spec
    nodeSelector   = { "ingress-ready" = "true" }
    tolerations    = [{ key = "node-role.kubernetes.io/control-plane", effect = "NoSchedule" }]
    ingressClass   = { enabled = true, isDefaultClass = false }
    # A ClusterIP Service has no external address to copy into Ingress status, and
    # Argo CD reports an Ingress without one as Progressing forever. On kind the real
    # entry point is localhost (hostPort), so publish that.
    providers = {
      kubernetesIngress = {
        publishedService = { enabled = false }
        ingressEndpoint  = { hostname = "localhost" }
      }
    }
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

# --- GitOps: Argo CD ----------------------------------------------------------------
# Terraform installs Argo CD and points it at Git ONCE (root app). From then on every
# change to what runs in the cluster is a Git commit.

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.chart_versions.argocd
  wait             = true

  values = [yamlencode({
    dex           = { enabled = false } # no SSO locally; on AWS: Dex/OIDC -> company IdP
    notifications = { enabled = false }
    configs = {
      params = { "server.insecure" = true } # local only: accessed via port-forward
      cm     = { "timeout.reconciliation" = "60s" }
    }
  })]
}

# Read access to the private repo for Argo CD (label makes Argo CD pick it up).
resource "kubernetes_secret_v1" "argocd_repo" {
  metadata {
    name      = "repo-weather"
    namespace = "argocd"
    labels    = { "argocd.argoproj.io/secret-type" = "repository" }
  }
  data = {
    type     = "git"
    url      = var.github_repo_url
    username = var.github_username
    password = var.github_token
  }
  depends_on = [helm_release.argocd]
}

# Pull secret for private GHCR images.
resource "kubernetes_secret_v1" "ghcr_pull" {
  metadata {
    name      = "ghcr-pull"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }
  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "ghcr.io" = { auth = base64encode("${var.github_username}:${var.github_token}") }
      }
    })
  }
}

resource "helm_release" "argocd_root" {
  name      = "argocd-root"
  namespace = "argocd"
  chart     = "${path.module}/../../charts/manifests"

  values = [yamlencode({
    manifests = [{
      apiVersion = "argoproj.io/v1alpha1"
      kind       = "Application"
      metadata   = { name = "root", namespace = "argocd" }
      spec = {
        project     = "default"
        source      = { repoURL = var.github_repo_url, targetRevision = "main", path = "deploy/argocd/local" }
        destination = { server = "https://kubernetes.default.svc", namespace = "argocd" }
        syncPolicy  = { automated = { prune = true, selfHeal = true } }
      }
    }]
  })]

  depends_on = [kubernetes_secret_v1.argocd_repo, helm_release.database]
}
