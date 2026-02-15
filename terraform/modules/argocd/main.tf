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


#This helps to get the DNS name of the loadbalancer
data "kubernetes_service_v1" "nginx_ingress_controller" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = "ingress-nginx"

  }
}

data "aws_lb" "nginx_ingress_nlb" {
  name = replace(
    data.kubernetes_service_v1.nginx_ingress_controller.status[0].load_balancer[0].ingress[0].hostname,
    "/\\..*/",
    ""
  )
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
  create_namespace = true
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
        "server.insecure" = true }
      }
    })
  ]

  depends_on = [var.cluster_name]

}

resource "aws_secretsmanager_secret" "argocd_admin" {
  name        = "argocd-admin"
  description = "Argocd admin password"
}

resource "aws_secretsmanager_secret_version" "argocd_admin_version" {
  secret_id = aws_secretsmanager_secret.argocd_admin.id
  secret_string = jsonencode({
    password = var.pass
  })
  ##The actual Password = MySecurePassword123!
}
##Protect Argocd Password using ESO

resource "kubectl_manifest" "external_secret" {
  yaml_body = <<EOF

apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: argocd-admin-secret
  namespace: argo-cd
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: secretstore
    kind: ClusterSecretStore
  target:
    name: argocd-secret
  data:
    - secretKey: admin.password
      remoteRef:
        key: argocd-admin
        property: password
EOF
}


###Route 53 dns records for ArgoCD (pointing to NGINX Ingress NLB)

resource "aws_route53_record" "argocd" {
  zone_id = data.aws_route53_zone.domain.zone_id
  name    = "argocd.mubashir.site"
  type    = "A"

  alias {
    name                   = data.aws_lb.nginx_ingress_nlb.dns_name
    zone_id                = data.aws_lb.nginx_ingress_nlb.zone_id
    evaluate_target_health = true
  }
}

resource "kubectl_manifest" "argocd-ingress" {
  yaml_body = <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd
  namespace: argo-cd
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-staging
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - argocd.mubashir.site 
      secretName: argocd-argocd-tls
  rules:
  - host: argocd.mubashir.site
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 8080
EOF
}