variable "vpc_cidr" {
  default = "10.0.0.0/16"
  type    = string
}

variable "enable_host" {
  default = true
  type    = bool
}

variable "enable_support" {
  default = true
  type    = bool
}


variable "cluster_name" {
  type    = string
  default = "eks-cluster"
}

variable "nodes_name" {
  type    = string
  default = "eks-nodes"
}

variable "cert_issuer" {
  description = "Which lets encrypt clusterissuer to use"
  type        = string
  default     = "letsencrypt-prod"
}


variable "pub_cidr_2a" {
  type    = string
  default = "10.0.1.0/24"
}

variable "pub_cidr_2b" {
  type    = string
  default = "10.0.2.0/24"
}

variable "priv_cidr_2c" {
  type    = string
  default = "10.0.3.0/24"
}

variable "priv_cidr_2d" {
  type    = string
  default = "10.0.4.0/24"
}


variable "avai_zone_2a" {
  type    = string
  default = "eu-west-2a"
}

variable "avai_zone_2b" {
  type    = string
  default = "eu-west-2b"
}


variable "inst_tenancy" {
  type    = string
  default = "default"
}


variable "vpc_flow_logs_role" {
  type = string
}