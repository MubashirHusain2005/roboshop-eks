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

data "aws_route53_zone" "domain" {
  name         = "mubashir.site"
  private_zone = false
}

locals {
  istio_charts_url = "https://istio-release.storage.googleapis.com/charts"
}


resource "kubectl_manifest" "istio_namespace" {
  yaml_body = <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: istio-system
EOF
}

resource "helm_release" "istio_base" {
  name             = "istio-base"
  repository       = local.istio_charts_url
  chart            = "base"
  namespace        = "istio-system"
  create_namespace = false
  version          = "1.29.0"
  timeout          = 120
  cleanup_on_fail  = true
  force_update     = false

  depends_on = [kubectl_manifest.istio_namespace]

}

resource "helm_release" "istiod" {

  name            = "istiod"
  chart           = "istiod"
  repository      = local.istio_charts_url
  namespace       = "istio-system"
  version         = "1.29.0"
  timeout         = 120
  cleanup_on_fail = true
  force_update    = false

  values = [
    file(var.istiod_values_file)
  ]


  depends_on = [helm_release.istio_base, helm_release.jaeger_operator,
    kubectl_manifest.jaeger, kubectl_manifest.istio_namespace
  ]

}

resource "helm_release" "istio_ingress" {
  name            = "istio-ingress"
  chart           = "gateway"
  namespace       = "istio-system"
  repository      = local.istio_charts_url
  version         = "1.29.0"
  timeout         = 500
  cleanup_on_fail = true
  force_update    = false

  depends_on = [helm_release.istiod, kubectl_manifest.istio_namespace]
}

##Addons

##UI to see service mesh 
resource "helm_release" "kiali" {
  name             = "kiali-server"
  chart            = "kiali-server"
  repository       = "https://kiali.org/helm-charts"
  namespace        = "istio-system"
  create_namespace = true

  set = [
    {
      name  = "auth.strategy"
      value = "anonymous"
    },
    {
      name  = "deployment.metrics.enabled"
      value = "true"
    },
    {
      name  = "external_services.prometheus.url"
      value = "http://prometheus-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090"
    },
    {
      name  = "rbac.clusterRole"
      value = "true"
    },
    {
      name  = "external_services.tracing.url"
      value = "http://my-jaeger-query.jaeger.svc.cluster.local:16686"
    }
  ]

  depends_on = [helm_release.istiod, helm_release.jaeger_operator, kubectl_manifest.jaeger]

}


###Jaeger for Latency Monitoring between Microservices

resource "kubectl_manifest" "jaeger_namespace" {
  yaml_body = <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: jaeger
EOF
}


resource "helm_release" "jaeger_operator" {
  name             = "jaegertracing"
  chart            = "jaeger-operator"
  repository       = "https://jaegertracing.github.io/helm-charts"
  version          = "2.25.0"
  create_namespace = false
  namespace        = "jaeger"

  set = [
    {
      name  = "rbac.clusterRole"
      value = true
    }
  ]
  depends_on = [kubectl_manifest.jaeger_namespace]
}

resource "kubectl_manifest" "jaeger" {
  yaml_body = <<EOF
apiVersion: jaegertracing.io/v1
kind: Jaeger
metadata:
  name: my-jaeger
  namespace: jaeger
spec:
  strategy: allInOne
  allInOne:
    image: jaegertracing/all-in-one:1.54
    options:
      log-level: info
  storage:
    type: memory
    options:
      memory:
        max-traces: 100000
  ingress:
    enabled: false
EOF

  depends_on = [helm_release.jaeger_operator]
}

