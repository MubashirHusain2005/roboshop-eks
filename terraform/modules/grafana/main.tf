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
    var.monitoring_namespace,
    var.prometheus_helmchart
  ]
}

