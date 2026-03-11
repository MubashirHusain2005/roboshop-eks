terraform {
  required_providers {

    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.2.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12.0"
    }

    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.7.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }

  }
}


resource "kubectl_manifest" "monitoring_namespace" {
  yaml_body = <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
EOF
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


  depends_on = [var.cluster_name,
    kubectl_manifest.monitoring_namespace,
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
    kubectl_manifest.mysql_exporter_my_cnf,
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
    kubectl_manifest.redis_secret,
  ]
}


resource "kubectl_manifest" "mysql_exporter_my_cnf" {
  yaml_body = <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: mysql-exporter-mycnf
  namespace: monitoring
type: Opaque
stringData:
  .my.cnf: |
    [client]
    user=metrics_user
    password=metrics_password
    host=mysql.app-space.svc.cluster.local
EOF

  depends_on = [var.cluster_endpoint]
}


resource "kubectl_manifest" "redis_secret" {
  yaml_body = <<EOF

apiVersion: v1
kind: Secret
metadata:
  name: redis-secret
  namespace: data-space
type: Opaque
stringData:
  REDIS_PASSWORD: redispassword 
EOF
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
      expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
      for: 2m
      labels:
        severity: critical
      annotations:
        description: "Node CPU usage above 80%"

    - alert: HighNodeMemory
      expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
      for: 2m
      labels:
        severity: critical
      annotations:
        description: "Node memory usage above 85%"
    
    - alert: PodRestart
      expr: kube_pod_container_status_restarts_totals > 2
      for: 0m
      labels:
        severity: critical
      annotations:
        description: "Pod restart detected"


EOF

  depends_on = [helm_release.prometheus]

}