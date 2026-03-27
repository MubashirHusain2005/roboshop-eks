terraform {
  backend "s3" {
    bucket       = "terraformstatebucket00534353432534523"
    key          = "envs/dev/eks/terraform.tfstate"
    region       = "eu-west-2"
    encrypt      = true
    use_lockfile = true
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
  region = var.region
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
  private_subnet_ids   = values(module.vpc.private_subnet_ids)
  kms_key_arn       = module.vpc.kms_key_arn
  node_group_name   = var.node_group_name
  node_group_name_2 = var.node_group_name_2
  depends_on        = [module.iam, module.vpc]
}


module "karpenter" {

  source                = "./modules/karpenter"
  node_instance_profile = module.iam.node_instance_profile.name
  cluster_id            = module.eks.cluster_id
  oidc_provider_arn     = module.eks.oidc_provider_arn
  oidc_issuer_url       = module.eks.oidc_issuer_url
  private_node_1_name   = module.eks.private_node_1_name
  private_node_2_name   = module.eks.private_node_2_name
  cluster_endpoint      = module.eks.cluster_endpoint
  nodegroup_role_arn    = module.iam.nodegroup_role_arn


  depends_on = [module.eks, module.iam]
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


module "cert-manager" {
  source = "./modules/cert-manager"

  cluster_endpoint         = module.eks.cluster_endpoint
  private_node_1_name      = module.eks.private_node_1_name
  private_node_2_name      = module.eks.private_node_2_name
  cert_manager_values_file = "${path.root}/../robotshop-application/cert-manager-values.yaml"
  oidc_provider_arn        = module.eks.oidc_provider_arn
  oidc_issuer_url          = module.eks.oidc_issuer_url

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
  private_node_1_name      = module.eks.private_node_1_name
  private_node_2_name      = module.eks.private_node_2_name
  external_dns_values_file = "${path.root}/../robotshop-application/external-dns-values.tpl.yaml"

  depends_on = [
    module.eks
  ]
}

module "argocd" {
  source = "./modules/argocd"

  cluster_name        = module.eks.cluster_name
  private_node_1_name = module.eks.private_node_1_name
  private_node_2_name = module.eks.private_node_2_name

  depends_on = [module.eks, module.istio, module.eso, module.external-dns, module.cert-manager, module.karpenter]
}


module "istio" {
  source             = "./modules/istio"
  istiod_values_file = "${path.root}/../robotshop-application/istiod-values.yaml"
  cluster_id         = module.eks.cluster_id
}

module "monitoring" {
  source                 = "./modules/monitoring"
  cluster_name           = module.eks.cluster_name
  monitoring_namespace   = var.monitoring_namespace
  private_node_1_name    = module.eks.private_node_1_name
  private_node_2_name    = module.eks.private_node_2_name
  cluster_endpoint       = module.eks.cluster_endpoint
  prometheus_values_file = "${path.root}/../robotshop-application/prometheus-values.yaml"

  depends_on = [module.eks, module.istio, module.eso]
}

module "eso" {
  source = "./modules/eso"

  cluster_endpoint             = module.eks.cluster_endpoint
  oidc_issuer_url              = module.eks.oidc_issuer_url
  oidc_provider_arn            = module.eks.oidc_provider_arn
  private_node_1_name          = module.eks.private_node_1_name
  private_node_2_name          = module.eks.private_node_2_name
  external_secrets_values_file = "${path.root}/../robotshop-application/eso-values.yaml"
  kms_key_id                   = module.vpc.kms_key_id
  depends_on                   = [module.eks]
}


# Cleanup Null Resources

resource "null_resource" "cleanup_script" {
  provisioner "local-exec" {
    command = <<EOT
      aws eks update-kubeconfig --region eu-west-2 --name eks-cluster
      kubectl delete validatingwebhookconfiguration externalsecret-validate
    EOT
    when    = destroy
  }
}
#aws eks update-kubeconfig --region eu-west-2 --name eks-cluster


###Null resource to update my kubeconfig file-has to run seperately if using github actions

resource "null_resource" "update_kubeconfig" {
  provisioner "local-exec" {
    command = "aws eks --region eu-west-2 update-kubeconfig --name eks-cluster"

  }
  depends_on = [module.eks]

}



