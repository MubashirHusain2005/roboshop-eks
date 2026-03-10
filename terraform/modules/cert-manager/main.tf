##  Cert manager
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

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  version          = "1.16.1"
  create_namespace = true
  wait             = true
  timeout          = 600

  values = [templatefile(var.cert_manager_values_file, {})]

  depends_on = [var.cluster_endpoint]
}


resource "kubectl_manifest" "istio_clusterissuer_staging" {
  yaml_body = <<EOF

apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    email: stokemubashir@gmail.com
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-staging-cluster
    solvers:
    - http01:
        ingress:
          class: istio
EOF

  depends_on = [helm_release.cert_manager]
}

resource "kubectl_manifest" "istio_clusterissuer_prod" {
  yaml_body  = <<EOF

apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: stokemubashir@gmail.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: istio
EOF
  depends_on = [helm_release.cert_manager]
}


#resource "kubectl_manifest" "certificate_prod" {
#yaml_body = <<EOF
#apiVersion: cert-manager.io/v1
#kind: Certificate
#metadata:
# name: mubashir-site-cert
# namespace: istio-system
#spec:
# secretName: mubashir-tls
# issuerRef:
#  name: letsencrypt-prod
#  kind: ClusterIssuer
#dnsNames:
# - mubashir.site
# - argocd.mubashir.site
# - grafana.mubashir.site
# - prometheus.mubashir.site
# - jaeger.mubashir.site
# - kiali.mubashir.site
#EOF
#}


#3  Cluster_issuer yaml file
#resource "kubectl_manifest" "letsencrypt_staging" {
#yaml_body = <<EOF
#apiVersion: cert-manager.io/v1
#kind: ClusterIssuer
#metadata:
#name: letsencrypt-staging
#spec:
#acme:
#server: https://acme-staging-v02.api.letsencrypt.org/directory
#email: stokemubashir@gmail.com
#privateKeySecretRef:
#name: letsencrypt-nginx-cert-staging
#solvers:
#- http01:
#ingress:
#class: nginx
#EOF

#depends_on = [
#helm_release.cert_manager
#]
#}

##For time being
#resource "kubectl_manifest" "letsencrypt_prod" {
#yaml_body = <<EOF
#apiVersion: cert-manager.io/v1
#kind: ClusterIssuer
#metadata:
# name: letsencrypt-prod
#spec:
#acme:
# server:  https://acme-v02.api.letsencrypt.org/directory
# email: stokemubashir@gmail.com
# privateKeySecretRef:
#  name: letsencrypt-nginx-cert
#solvers:
# - http01:
#   ingress:
#   class: nginx
#EOF

# depends_on = [
# helm_release.cert_manager
# ]
#}