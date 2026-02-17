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


resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  namespace  = var.monitoring_namespace
  version    = "7.3.7"

  create_namespace = false
  wait             = false
  atomic           = false
  cleanup_on_fail  = false
  timeout          = 300

  depends_on = [var.cluster_name,
  var.monitoring_namespace]
}



resource "kubectl_manifest" "grafana_ingress" {
  yaml_body  = <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana
  namespace: monitoring
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-staging
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    external-dns.alpha.kubernetes.io/hostname: grafana.mubashir.site
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - grafana.mubashir.site 
      secretName: grafana-grafana-tls
  rules:
  - host: grafana.mubashir.site
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: grafana
            port:
              number: 80

EOF
  depends_on = [helm_release.grafana]

}