terraform {
  backend "s3" {
    bucket  = "terraformstatebucket00534353432534523"
    key     = "envs/dev/eks/terraform.tfstate"
    region  = "eu-west-2"
    encrypt = true
  }
  required_version = "1.13.3"

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


provider "aws" {
  region = "eu-west-2"
}



module "iam" {
  source = "./modules/iam"
}

module "vpc" {
  source             = "./modules/vpc"
  vpc_flow_logs_role = module.iam.vpc_flow_logs_role
  depends_on         = [module.iam]
}

module "eks" {
  source               = "./modules/eks"
  clus_vers            = var.clus_vers
  vpc_id               = module.vpc.vpc_id
  iam_cluster_role_arn = module.iam.iam_cluster_role_arn
  nodegroup_role_arn   = module.iam.nodegroup_role_arn
  priv_subnet2a_id     = module.vpc.priv_subnet2a_id
  priv_subnet2b_id     = module.vpc.priv_subnet2b_id
  kms_key_arn          = module.vpc.kms_key_arn
  node_group_name      = var.node_group_name
  node_group_name_2    = var.node_group_name_2
  depends_on           = [module.iam, module.vpc]
}

module "security-group" {
  source = "./modules/security-group"
  vpc_id = module.vpc.vpc_id
}



provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.eks.cluster_name,
      "--region",
      "eu-west-2"
    ]
  }
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--cluster-name",
        module.eks.cluster_name,
        "--region",
        "eu-west-2"
      ]
    }
  }
}

provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.eks.cluster_name,
      "--region",
      "eu-west-2"
    ]
  }
}

# =========================================
# Kubernetes Modules (after cluster creation)
# =========================================

module "cert-manager" {
  source = "./modules/cert-manager"

  cluster_endpoint         = module.eks.cluster_endpoint
  private_node_1_name      = module.eks.private_node_1_name
  private_node_2_name      = module.eks.private_node_2_name
  cert_manager_values_file = "${path.root}/../robotshop-application/cert-manager-values.yaml"

  depends_on = [
    module.eks,
    module.nginx-ingress
  ]
}

module "nginx-ingress" {
  source = "./modules/nginx-ingress"

  cluster_endpoint    = module.eks.cluster_endpoint
  private_node_1_name = module.eks.private_node_1_name
  private_node_2_name = module.eks.private_node_2_name
  nginx_values_file = "${path.root}/../robotshop-application/nginx-values.yaml"

  depends_on = [
    module.eks
  ]
}

module "external-dns" {
  source = "./modules/external-dns"

  oidc_issuer_url          = module.eks.oidc_issuer_url
  oidc_provider_arn        = module.eks.oidc_provider_arn
  external_dns_policy_name = var.external_dns_policy_name
  external_dns_name        = var.external_dns_name
  external_dns_ns          = var.external_dns_ns
  external_dns_rolename    = var.external_dns_rolename
  helm_release_nginx       = module.nginx-ingress.helm_release_nginx
  private_node_1_name      = module.eks.private_node_1_name
  private_node_2_name      = module.eks.private_node_2_name
  external_dns_values_file = "${path.root}/../robotshop-application/external-dns-values.tpl.yaml"

   depends_on = [
    module.eks,
    module.nginx-ingress
  ]
}

module "argocd" {
  source = "./modules/argocd"

  cluster_name        = module.eks.cluster_name
  helm_release_nginx  = module.nginx-ingress.helm_release_nginx
  private_node_1_name = module.eks.private_node_1_name
  private_node_2_name = module.eks.private_node_2_name

 depends_on = [module.eks]
}

module "prometheus" {
  source = "./modules/prometheus"

  cluster_name           = module.eks.cluster_name
  cluster_endpoint       = module.eks.cluster_endpoint
  private_node_1_name    = module.eks.private_node_1_name
  private_node_2_name    = module.eks.private_node_2_name
  prometheus_values_file = "${path.root}/../robotshop-application/prometheus-values.yaml"

  depends_on = [module.eks]
}

module "grafana" {
  source = "./modules/grafana"

  cluster_name         = module.eks.cluster_name
  monitoring_namespace = module.prometheus.monitoring_namespace
  prometheus_helmchart = module.prometheus.prometheus_helmchart
  private_node_1_name  = module.eks.private_node_1_name
  private_node_2_name  = module.eks.private_node_2_name

  depends_on = [module.prometheus]
}

module "eso" {
  source = "./modules/eso"

  cluster_endpoint             = module.eks.cluster_endpoint
  oidc_issuer_url              = module.eks.oidc_issuer_url
  oidc_provider_arn            = module.eks.oidc_provider_arn
  private_node_1_name          = module.eks.private_node_1_name
  private_node_2_name          = module.eks.private_node_2_name
  external_secrets_values_file = "${path.root}/../robotshop-application/eso-values.yaml"
  depends_on                   = [module.eks]
}

# =========================================
# Cleanup Null Resources
# =========================================
resource "null_resource" "cleanup_script" {
  provisioner "local-exec" {
    command = "kubectl delete validatingwebhookconfiguration externalsecret-validate"
    when    = destroy
  }

  depends_on = [module.eks]
}

resource "null_resource" "cleanup_secrets" {
  provisioner "local-exec" {
    command = "aws secretsmanager delete-secret --secret-id db-creds --force-delete-without-recovery"
    when    = destroy
  }
}

###Null resource to update my kubeconfig file

resource "null_resource" "update_kubeconfig" {
  provisioner "local-exec" {
    command = "aws eks --region eu-west-2 update-kubeconfig --name eks-cluster"

  }
  depends_on = [module.eks]

}


##Clean deletion of helm charts

## Clean deletion of Helm charts

resource "null_resource" "cleanup_helm" {
  # This triggers every time we destroy this resource
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = "./delete.sh"
    when    = destroy
  }
}