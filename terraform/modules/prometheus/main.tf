terraform {
  required_providers {

    aws = {
      source = "hashicorp/aws"
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

  }
}

data "kubernetes_service" "redis_service" {
  metadata {
    name = "redis"
    namespace = "data-space"
  }
}

data "kubernetes_service" "mysql_service" {
  metadata {
    name = "mysql"
    namespace = "app-space"
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
      mysql = {
        host           = "mysql.app-space.svc.cluster.local"
        user           = "metrics_user"
        existingSecret = "mysql-exporter-secret"
        passwordKey    = "MYSQL_PASSWORD"
      }

      serviceMonitor = {
        enabled = true
        additionalLabels = {
          release = "prometheus"
        }
      }
    })
  ]

  depends_on = [helm_release.prometheus,
  kubectl_manifest.mysql_exporter_secret,
  data.kubernetes_service.mysql_service]
}



###Redis exporter to collect metrics
resource "helm_release" "redis_exporter" {
  name       = "redis-exporter"
  namespace  = "monitoring"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus-redis-exporter"
  version    = "6.21.0"  

  values = [
    yamlencode({
      redisAddress = "redis://redis.data-space.svc.cluster.local:6379"

      existingSecret = "redis-secret"
      existingSecretPasswordKey = "REDIS_PASSWORD"

      serviceMonitor = {
        enabled = true
        namespace = "monitoring"
        interval = "15s"
        labels = {
          release = "prometheus"
        }
      }
    })
  ]

  # Make sure the release is installed after any dependencies (optional)
  depends_on = [
    helm_release.prometheus,
    kubectl_manifest.redis_secret,
    data.kubernetes_service.redis_service
  ]
}

##Temporary K8s job- this will allow the exporter to temporarily authenticate to the mysql server so we can scrape metrics

resource "kubectl_manifest" "mysql_exporter_auth" {
  yaml_body = <<EOF

apiVersion: batch/v1
kind: job
metadata:
  name: mysql-exporter-authentication
  namespace: app-space
spec:
  template:
    spec:
      containers:
      - name: mysql-client
        image: 038774803581.dkr.ecr.eu-west-2.amazonaws.com/mysql:v1
        command:
        - sh
        - -c
        - |
          mysql -h mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "
          CREATE USER IF NOT EXISTS 'metrics_user'@'%' IDENTIFIED BY 'metrics_password';
          GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'metrics_user'@'%';
          FLUSH PRIVILEGES;"
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: root-password
    restartPolicy: OnFailure

EOF

  depends_on = [kubectl_manifest.mysql_exporter_secret ]
}



resource "kubectl_manifest" "mysql_exporter_secret" {
  yaml_body = <<EOF

apiVersion: v1
kind: Secret
metadata:
  name: mysql-exporter-secret
  namespace: monitoring
type: Opaque
stringData:
  MYSQL_PASSWORD: metrics_password 
EOF
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


##Service Monitors for Deployments to scrape metrics

#resource "kubectl_manifest" "mysql_service_monitor" {
    #yaml_body = <<EOF

#apiVersion: monitoring.coreos.com/v1
#kind: ServiceMonitor
#metadata:
  #name: mysql-exporter
  #namespace: app-space
  #labels:
    #release: monitoring
#spec:
  #selector:
    #matchLabels:
      #app: mysql
  #endpoints:
   # - port: metrics
     # interval: 15s

#EOF
#}

resource "kubectl_manifest" "prometheus_ingress" {
  yaml_body  = <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: prometheus
  namespace: monitoring
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-staging
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    external-dns.alpha.kubernetes.io/hostname: prometheus.mubashir.site
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - prometheus.mubashir.site 
      secretName: prometheus-prometheus-tls
  rules:
  - host: prometheus.mubashir.site
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: prometheus-kube-prometheus-prometheus
            port:
              number: 9090

EOF
  depends_on = [helm_release.prometheus]

}

