##  Cert manager
terraform {
  required_providers {

    aws = {
      source = "hashicorp/aws"
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
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = "cert-manager"
  version    = "1.16.1"

  create_namespace = true
  wait             = true
  timeout          = 600



  values = [templatefile(var.cert_manager_values_file, {})]



  depends_on = [var.cluster_endpoint]
}


#3  Cluster_issuer yaml file
resource "kubectl_manifest" "letsencrypt_staging" {
  yaml_body = <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: stokemubashir@gmail.com
    privateKeySecretRef:
      name: letsencrypt-nginx-cert-staging
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

  depends_on = [
    helm_release.cert_manager
  ]
}

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