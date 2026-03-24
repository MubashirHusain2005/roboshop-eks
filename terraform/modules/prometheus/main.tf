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

##Calls existing secret store from AWS
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
    #kubectl_manifest.redis_secret,
  ]
}


#resource "kubectl_manifest" "mysql_exporter_my_cnf" {
#yaml_body = <<EOF
#apiVersion: v1
#kind: Secret
#metadata:
#name: mysql-exporter-mycnf
#namespace: monitoring
#type: Opaque
#stringData:
# .my.cnf: |
#  [client]
# user=metrics_user
#password=metrics_password
#host=mysql.app-space.svc.cluster.local
#EOF

# depends_on = [var.cluster_endpoint]
#}


#resource "kubectl_manifest" "redis_secret" {
#yaml_body = <<EOF

#apiVersion: v1
#kind: Secret
#metadata:
# name: redis-secret
#namespace: monitoring  ##was data-space 
#type: Opaque
#stringData:
#REDIS_PASSWORD: redispassword 
#EOF
#}


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


#1. Create MySQL user: metrics_user
#2. Store credentials in AWS Secret
#3. ESO syncs to K8s Secret
#4. Mount as /home/.my.cnf
#5. Exporter reads credentials
#6. Exporter authenticates to MySQL
##7. MySQL gives exporter its internal metrics
#8. Exporter exposes on /metrics endpoint
#9. Prometheus scrapes
#10. You see what's happening in MySQL!


#Complete Redis Metric Collection Flow

#Stage 1: Infrastructure Setup

##Redis StatefulSet deployed in data-space namespace
#Redis Service created (registers in K8s DNS as redis.data-space.svc.cluster.local)
#Service points to Redis pods via selector labels

#Stage 2: Exporter Secrets

#ESO syncs Redis password from AWS Secrets Manager
#Creates K8s Secret redis-exporter-credentials in monitoring namespace
#Exporter mounts this secret as a volume

#Stage 3: Redis Exporter Deployment

#Redis Exporter Helm chart deployed in monitoring namespace
#Exporter configured with redisAddress = "redis://redis.data-space.svc.cluster.local:6379"
#Exporter mounts the K8s Secret containing Redis password
#Exporter pod starts running

#Stage 4: DNS Resolution & Connection

#Exporter makes network call to redis://redis.data-space.svc.cluster.local:6379
#Kubernetes DNS server intercepts the request
#DNS resolves the FQDN to the Redis Service IP (e.g., 10.0.5.123)
#Network traffic sent to that IP:6379
#Redis Service forwards traffic to Redis pod
#Exporter authenticates using password from mounted secret ✅

#Stage 5: Metric Collection

#Exporter connects to Redis
#Exporter queries Redis for metrics (commands like INFO, CONFIG GET, etc.)
#Redis responds with internal metrics
#Exporter converts to Prometheus format (text format with HELP and TYPE)
#Exporter exposes metrics on /metrics endpoint (port 9121)

#Stage 6: ServiceMonitor Discovery

#ServiceMonitor created by redis-exporter Helm chart
#ServiceMonitor has label: release: prometheus
#Prometheus looks for ServiceMonitors matching its selector labels
#Prometheus finds the ServiceMonitor (labels match!)

#Stage 7: Prometheus Scraping

#Prometheus discovers the redis-exporter service via ServiceMonitor
#Prometheus scrapes the /metrics endpoint every 15 seconds (your interval)
#Prometheus receives metrics in text format

##Stage 8: Storage

#Prometheus stores metrics in its Time-Series Database (TSDB)
#Metrics stored with labels (e.g., redis instance, metric name, timestamp)
#Data persists on attached storage (if configured with PVC)

#Stage 9: Querying & Alerting

#Alert rules continuously evaluate metrics stored in TSDB
#If alert conditions met → Alert fires
#AlertManager routes alert (e.g., to email)

#Password protects Redis from unauthorized access. 
#Any pod (even malicious ones) needs the correct credentials to connect. 
#It's a basic security requirement.