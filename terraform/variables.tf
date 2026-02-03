variable "region" {
  type    = string
  default = "eu-west-2"
}

variable "clus_vers" {
  default = "1.30"
  type    = string
}

variable "cluster_name" {
  type    = string
  default = "eks-cluster"
}

variable "node_group_name" {
  type    = string
  default = "eks-node-group-1"
}

variable "node_group_name_2" {
  type    = string
  default = "eks-node-group-2"
}


variable "external_dns_policy_name" {
  type    = string
  default = "external-dns-route53-policy"
}


variable "external_dns_name" {
  type    = string
  default = "external-dns"
}

variable "external_dns_ns" {
  type    = string
  default = "external-dns"
}

variable "external_dns_rolename" {
  type    = string
  default = "iam-dns"
}

variable "cert_name" {
  type    = string
  default = "cert-manager"
}

