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

resource "kubectl_manifest" "argo_namespace" {
  yaml_body = <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: argo-cd
EOF
}


data "aws_eks_cluster_auth" "main" {
  name = var.cluster_name
}


data "aws_route53_zone" "domain" {
  name         = "mubashir.site"
  private_zone = false
}

resource "helm_release" "argocd_deploy" {
  name             = "argocd"
  namespace        = "argo-cd"
  create_namespace = false
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.6.6"
  timeout          = "600"

  values = [
    yamlencode({
      server = {
        service = {
          type = "ClusterIP"
        }

      }

      configs = {
        params = {
          "server.insecure"   = true
          "server.localUsers" = true
        }
      }

      secret = {
        argocdServerAdminPassword = "$2a$10$Jsn3fOA5LWlmPf3bsfeom.3aXbdSd.ybCmvL4TYTh76IlRqRI2GNK"
      }

      dex = {
        enabled = false
      }
    })
  ]

  depends_on = [var.cluster_name]

}

resource "kubectl_manifest" "robot_app" {
  yaml_body = <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: robotshop-app
  namespace: argo-cd
spec:
  project: default
  source:
    repoURL: https://github.com/MubashirHusain2005/roboshop-eks.git
    targetRevision: master
    path: robotshop-application
    helm:
      valueFiles:
        - values.yml
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

  depends_on = [
    helm_release.argocd_deploy
  ]
}


#resource "aws_secretsmanager_secret" "argocd_admin" {
#name        = "argocd-admin"
#description = "Argocd admin password"
#}

#resource "aws_secretsmanager_secret_version" "argocd_admin_version" {
#secret_id = aws_secretsmanager_secret.argocd_admin.id
#secret_string = jsonencode({
#password = "MySecurePassword123!"
#})

##The actual Password = MySecurePassword123!
#}
##Protect Argocd Password using ESO

#resource "kubectl_manifest" "external_secret" {
#yaml_body = <<EOF

#apiVersion: external-secrets.io/v1beta1
#kind: ExternalSecret
#metadata:
# name: argocd-admin-secret
# namespace: argo-cd
#spec:
# refreshInterval: 1h
# secretStoreRef:
# name: secretstore
# kind: ClusterSecretStore
# target:
# name: argocd-secret
# creationPolicy: Owner
# data:
# - secretKey: admin.password
#  remoteRef:
#  key: argocd-admin
# property: password
# - secretKey: server.secretkey
# remoteRef:
# key: argocd-admin
# property: server.secretkey
#EOF
#}



#resource "kubectl_manifest" "argocd-ingress" {
#yaml_body = <<EOF

#apiVersion: networking.k8s.io/v1
#kind: Ingress
#metadata:
#name: argocd
#namespace: argo-cd
#annotations:
#cert-manager.io/cluster-issuer: letsencrypt-staging
#cert-manager.io/acme-challenge-type: http01
# nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
#acme.cert-manager.io/http01-edit-in-place: "true"
#nginx.ingress.kubernetes.io/ssl-redirect: "true"
#external-dns.alpha.kubernetes.io/hostname: argocd.mubashir.site
#spec:
#ingressClassName: nginx
#rules:
#- host: argocd.mubashir.site
#http:
#paths:
#- path: /
#pathType: Prefix
#backend: 
#service:
#name: argocd-server
#port:
#number: 80
#tls:
# - hosts:
#- argocd.mubashir.site
# secretName: argocd-tls
#EOF
#}