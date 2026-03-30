data "aws_secretsmanager_secret" "prometheus_secrets" {
  name = var.prometheus_secret_name
}


##Promethues to collect core Kubernetes metrics
resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = "monitoring"
  version    = "55.5.0"

  create_namespace = false
  wait             = true
  atomic           = false
  cleanup_on_fail  = false
  timeout          = 300

  values = [
    file(var.prometheus_values_file)
  ]

}


##Prometheus Mysql Exporter to collect mysql metrics
resource "helm_release" "mysql_exporter" {
  name       = "mysql-exporter"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus-mysql-exporter"
  namespace  = "monitoring"
  version    = "1.10.0"

  values = [
    yamlencode({
      serviceMonitor = {
        enabled          = true
        additionalLabels = { release = "prometheus" }
      }
      extraVolumeMounts = [
        {
          name      = "mysql-mycnf"
          mountPath = "/home/.my.cnf"
          subPath   = ".my.cnf"
          readOnly  = true
        }
      ]
      extraVolumes = [
        {
          name = "mysql-mycnf"
          secret = {
            secretName = "mysql-exporter-mycnf"
          }
        }
      ]
    })
  ]

  depends_on = [
    helm_release.prometheus
  ]
}

###Redis exporter to collect redis metrics
resource "helm_release" "redis_exporter" {
  name       = "redis-exporter"
  namespace  = "monitoring"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus-redis-exporter"
  version    = "6.21.0"

  values = [
    yamlencode({
      redisAddress = "redis://redis.data-space.svc.cluster.local:6379"

      existingSecret            = "redis-secret"
      existingSecretPasswordKey = "REDIS_PASSWORD"

      serviceMonitor = {
        enabled   = true
        namespace = "monitoring"
        interval  = "15s"
        labels = {
          release = "prometheus"
        }
      }
    })
  ]

  depends_on = [
    helm_release.prometheus,
  ]
}


##Alerts
resource "kubectl_manifest" "prometheus_rule" {
  yaml_body = <<EOF

apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: node-resource-alerts
  namespace: monitoring
spec:
  groups:
  - name: node-alerts
    rules:

    - alert: HighNodeCPU
      expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 50
      for: 5m
      labels:
        severity: warning
      annotations:
        description: "Node CPU usage above 50%"

    - alert: HighNodeMemory
      expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 70
      for: 2m
      labels:
        severity: critical
      annotations:
        description: "Node memory usage above 70%"
    
    - alert: PodRestart
      expr: kube_pod_container_status_restarts_total > 2
      for: 5m
      labels:
        severity: warning
      annotations:
        description: "Pod restart detected"


EOF

  depends_on = [helm_release.prometheus]

}
