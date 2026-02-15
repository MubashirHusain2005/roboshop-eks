data "aws_eks_cluster_auth" "cluster_auth" {
  name = module.eks.cluster_name
}

module "vpc" {
  source             = "./modules/vpc"
  vpc_flow_logs_role = module.iam.vpc_flow_logs_role


  depends_on = [module.iam]
}


module "iam" {
  source = "./modules/iam"
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

  depends_on = [
    module.iam,
    module.vpc
  ]

}


module "cert-manager" {
  source           = "./modules/cert-manager"
  cluster_endpoint = module.eks.cluster_endpoint

  depends_on = [
    module.eks,
    module.nginx-ingress
  ]

}

module "external-dns" {
  source                   = "./modules/external-dns"
  oidc_issuer_url          = module.eks.oidc_issuer_url
  oidc_provider_arn        = module.eks.oidc_provider_arn
  external_dns_policy_name = var.external_dns_policy_name
  external_dns_name        = var.external_dns_name
  external_dns_ns          = var.external_dns_ns
  external_dns_rolename    = var.external_dns_rolename


  depends_on = [
    module.eks,
    module.nginx-ingress
  ]

}


module "nginx-ingress" {
  source           = "./modules/nginx-ingress"
  cluster_endpoint = module.eks.cluster_endpoint

  depends_on = [
    module.eks
  ]
}

module "security-group" {
  source = "./modules/security-group"
  vpc_id = module.vpc.vpc_id
}


module "argocd" {
  source             = "./modules/argocd"
  cluster_name       = module.eks.cluster_name
  helm_release_nginx = module.nginx-ingress.helm_release_nginx

  depends_on = [ module.eks ]
}





resource "null_resource" "cleanup_script" {
  provisioner "local-exec" {
    command = "kubectl delete validatingwebhookconfiguration externalsecret-validate"
    when = destroy

  }  
}

resource "null_resource" "cleanup_script2" {
    provisioner "local-exec" {
    command = "kubectl delete ingress -A"
    when = destroy
    }
}
