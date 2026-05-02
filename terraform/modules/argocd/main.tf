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

data "aws_secretsmanager_secret_version" "argocd" {
  secret_id = var.app_secrets
}

resource "kubectl_manifest" "argocd_namespace" {
  yaml_body = <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: argo-cd
EOF
}



resource "helm_release" "argocd_deploy" {
  name             = "argocd"
  namespace        = "argo-cd"
  create_namespace = false
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.6.6"
  timeout          = "600"
  replace          = true

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
        argocdServerAdminPassword = jsondecode(data.aws_secretsmanager_secret_version.argocd.secret_string)["argocdServerAdminPassword"]
      }

      dex = {
        enabled = false
      }
    })
  ]

  depends_on = [kubectl_manifest.argocd_namespace]

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
        - values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: app-space        
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true   
EOF

  depends_on = [
    helm_release.argocd_deploy
  ]
}


