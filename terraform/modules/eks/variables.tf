variable "cluster_name" {
  type    = string
  default = "eks-cluster"
}

variable "clus_vers" {
  type = string
}

variable "vpc_id" {
  type = string
}


variable "iam_cluster_role_arn" {
  type = string
}


variable "nodegroup_role_arn" {
  type = string
}

#variable "priv_sub_2c" {
#type    = string
#default = "10.0.3.0/24"
#}

#variable "priv_sub_2d" {
#type    = string
#default = "10.0.4.0/24"
#}


#variable "priv_subnet2a_id" {
#type = string
#}

#variable "priv_subnet2b_id" {
#type = string
#}

variable "private_subnet_ids" {
  type = list(string)
}

variable "kms_key_arn" {
  type        = string
  description = "KMS key ARN used for EKS secrets encryption"
}

variable "node_group_name" {
  type = string
}

variable "node_group_name_2" {
  type = string
}

variable "secrets" {
  default = {
    DB_USER       = "shipping"
    DB_PASSWORD   = "secret"
    root-password = "rootpass"
    user-password = "secret"

  }

  type = map(string)
}


#variable "oidc_provider_arn" {
# type = string
#}

#variable "oidc_issuer_url" {
# type = string
#}

variable "oidc_name" {
  type    = string
  default = "github.to.aws.oidc"
}