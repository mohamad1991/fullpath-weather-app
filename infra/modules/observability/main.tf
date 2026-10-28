# Metrics (Prometheus), alerting (Alertmanager), dashboards (Grafana), logs (Loki + Alloy).
# Same module locally and on AWS; only sizing and storage differ.
#
# Ownership split:
#   platform (this module): the stack, routing, cluster-level default rules
#   app teams (their Helm chart): ServiceMonitor, PrometheusRule, dashboards - versioned with the app

locals {
  namespace = "monitoring"

  slack_configs = var.slack_webhook_url == "" ? {} : {
    pager = [{
      api_url       = var.slack_webhook_url
      channel       = "#weather-oncall"
      send_resolved = true
      title         = "[{{ .Status | toUpper }}] {{ .CommonLabels.alertname }}"
      text          = "{{ range .Alerts }}*{{ .Annotations.summary }}*\n{{ .Annotations.description }}\nRunbook: {{ .Annotations.runbook_url }}\n{{ end }}"
    }]
    chat = [{
      api_url       = var.slack_webhook_url
      channel       = "#weather-alerts"
      send_resolved = true
      title         = "[{{ .Status | toUpper }}] {{ .CommonLabels.alertname }}"
      text          = "{{ range .Alerts }}*{{ .Annotations.summary }}*\n{{ .Annotations.description }}\nRunbook: {{ .Annotations.runbook_url }}\n{{ end }}"
    }]
  }

  loki_s3 = var.loki_s3_bucket != ""
}

resource "random_password" "grafana_admin" {
  length  = 24
  special = false
}

resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  namespace        = local.namespace
  create_namespace = true
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.chart_versions.kube_prometheus_stack
  wait             = true
  timeout          = 600

  values = [yamlencode({
    fullnameOverride = "kps"

    # Control plane is not scrapeable (kind: bound to localhost; EKS: AWS-managed).
    # Leaving these on yields permanently-firing "down" alerts - alert fatigue.
    kubeControllerManager = { enabled = false }
    kubeScheduler         = { enabled = false }
    kubeEtcd              = { enabled = false }
    kubeProxy             = { enabled = false }

    prometheus = {
      prometheusSpec = {
        # Pick up ServiceMonitors/PodMonitors/PrometheusRules from ANY namespace, not only
        # ones labelled for this Helm release: app teams ship monitoring with their chart.
        serviceMonitorSelectorNilUsesHelmValues = false
        podMonitorSelectorNilUsesHelmValues     = false
        ruleSelectorNilUsesHelmValues           = false
        replicas                                = var.prometheus_replicas
        retention                               = var.prometheus_retention
        resources = {
          requests = { cpu = "100m", memory = "512Mi" }
          limits   = { memory = "2Gi" }
        }
        storageSpec = var.prometheus_storage_size == "" ? null : {
          volumeClaimTemplate = {
            spec = {
              storageClassName = var.storage_class
              accessModes      = ["ReadWriteOnce"]
              resources        = { requests = { storage = var.prometheus_storage_size } }
            }
          }
        }
      }
    }

    alertmanager = {
      alertmanagerSpec = { replicas = var.alertmanager_replicas }
      config = {
        global = { resolve_timeout = "5m" }
        route = {
          receiver        = "null"
          group_by        = ["alertname", "namespace", "location"]
          group_wait      = "30s"
          group_interval  = "5m"
          repeat_interval = "4h"
          routes = [
            # Watchdog always fires: proves the pipeline works end to end. In production,
            # route it to a dead-man's-switch (e.g. healthchecks.io) that pages when it STOPS.
            { matchers = ["alertname = Watchdog"], receiver = "null" },
            { matchers = ["alertname = InfoInhibitor"], receiver = "null" },
            { matchers = ["severity = critical"], receiver = "pager" },
            { matchers = ["severity = warning"], receiver = "chat" },
          ]
        }
        # A critical alert silences its warning-level twin (no double notification).
        inhibit_rules = [{
          source_matchers = ["severity = critical"]
          target_matchers = ["severity = warning"]
          equal           = ["namespace", "location"]
        }]
        receivers = [
          { name = "null" },
          merge({ name = "pager" }, contains(keys(local.slack_configs), "pager") ? { slack_configs = local.slack_configs.pager } : {}),
          merge({ name = "chat" }, contains(keys(local.slack_configs), "chat") ? { slack_configs = local.slack_configs.chat } : {}),
        ]
      }
    }

    grafana = {
      adminPassword = random_password.grafana_admin.result
      replicas      = var.grafana_replicas
      sidecar = {
        dashboards = { enabled = true, searchNamespace = "ALL", label = "grafana_dashboard" }
      }
      additionalDataSources = [{
        name   = "Loki"
        type   = "loki"
        uid    = "loki"
        url    = "http://loki.${local.namespace}.svc:3100"
        access = "proxy"
      }]
    }
  })]
}

resource "helm_release" "loki" {
  name       = "loki"
  namespace  = local.namespace
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = var.chart_versions.loki
  wait       = true
  timeout    = 600

  values = [yamlencode({
    deploymentMode = "SingleBinary"
    loki = {
      auth_enabled = false
      commonConfig = { replication_factor = var.loki_replicas }
      schemaConfig = {
        configs = [{
          from         = "2024-01-01"
          store        = "tsdb"
          object_store = local.loki_s3 ? "s3" : "filesystem"
          schema       = "v13"
          index        = { prefix = "index_", period = "24h" }
        }]
      }
      storage       = { type = "filesystem" } # overridden by the S3 values document below on AWS
      limits_config = { retention_period = var.loki_retention }
      compactor = {
        retention_enabled    = true
        delete_request_store = local.loki_s3 ? "s3" : "filesystem"
      }
    }
    singleBinary = {
      replicas    = var.loki_replicas
      persistence = { enabled = true, size = "10Gi", storageClass = var.storage_class }
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "1Gi" }
      }
    }
    serviceAccount = { name = "loki" } # Pod Identity on AWS binds S3 access to this SA
    # SingleBinary only: switch off the scalable-mode components and extras.
    backend      = { replicas = 0 }
    read         = { replicas = 0 }
    write        = { replicas = 0 }
    gateway      = { enabled = false }
    chunksCache  = { enabled = false }
    resultsCache = { enabled = false }
    lokiCanary   = { enabled = false }
    test         = { enabled = false }
    minio        = { enabled = false }
  })]

  depends_on = [helm_release.kube_prometheus_stack] # namespace + ServiceMonitor CRDs
}

resource "helm_release" "alloy" {
  name       = "alloy"
  namespace  = local.namespace
  repository = "https://grafana.github.io/helm-charts"
  chart      = "alloy"
  version    = var.chart_versions.alloy
  wait       = true

  values = [yamlencode({
    # Tails logs through the Kubernetes API (loki.source.kubernetes): no privileged
    # DaemonSet / hostPath mounts. Scale out later with Alloy clustering.
    controller = { type = "deployment", replicas = 1 }
    alloy = {
      configMap = {
        content = <<-ALLOY
          discovery.kubernetes "pods" {
            role = "pod"
          }

          discovery.relabel "pods" {
            targets = discovery.kubernetes.pods.targets
            rule {
              source_labels = ["__meta_kubernetes_namespace"]
              target_label  = "namespace"
            }
            rule {
              source_labels = ["__meta_kubernetes_pod_name"]
              target_label  = "pod"
            }
            rule {
              source_labels = ["__meta_kubernetes_pod_container_name"]
              target_label  = "container"
            }
            rule {
              source_labels = ["__meta_kubernetes_pod_label_app_kubernetes_io_component"]
              target_label  = "component"
            }
          }

          loki.source.kubernetes "pods" {
            targets    = discovery.relabel.pods.output
            forward_to = [loki.process.json.receiver]
          }

          // App logs are JSON: lift "level" to a label so Grafana can filter on it.
          loki.process "json" {
            stage.json {
              expressions = { level = "level" }
            }
            stage.labels {
              values = { level = "" }
            }
            forward_to = [loki.write.default.receiver]
          }

          loki.write "default" {
            endpoint {
              url = "http://loki.${local.namespace}.svc:3100/loki/api/v1/push"
            }
          }
        ALLOY
      }
    }
  })]

  depends_on = [helm_release.loki]
}
