#terraform {
#required_providers {

# aws = {
#   source  = "hashicorp/aws"
#  version = ">= 6.2.0"
# }

# kubernetes = {
# source  = "hashicorp/kubernetes"
#version = ">= 2.23.0"
#}
#  helm = {
# source  = "hashicorp/helm"
# version = ">= 2.12.0"
# }

# kubectl = {
#  source  = "gavinbunney/kubectl"
#   version = ">= 1.7.0"
# }

# null = {
#   source  = "hashicorp/null"
#  version = "~> 3.2"
#}
#}
#}


## nginx-ingress controller

#resource "helm_release" "nginx_ingress" {
#name             = "ingress-nginx"
#namespace        = "ingress-nginx"
#create_namespace = true
#repository       = "https://kubernetes.github.io/ingress-nginx"
#chart            = "ingress-nginx"
# version          = "4.8.3"
# atomic           = false
#lint             = true
#wait             = true
#timeout          = 600


# values = [
#file(var.nginx_values_file)
# ]

# depends_on = [var.cluster_endpoint]
#}