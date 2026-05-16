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



variable "inst_tenancy" {
  type    = string
  default = "default"
}


variable "vpc_flow_logs_role" {
  type = string
}


variable "public_subnets" {
  type = map(object({
    cidr = string
    az   = string
  }))
  default = {
    "public-subnet-2a" = {
      cidr = "10.0.1.0/24"
      az   = "eu-west-2a"
    }
    "public-subnet-2b" = {
      cidr = "10.0.2.0/24"
      az   = "eu-west-2b"
    }
  }
}

variable "private_subnets" {
  type = map(object({
    cidr = string
    az   = string
  }))
  default = {
    "private-subnet-2a" = {
      cidr = "10.0.3.0/24"
      az   = "eu-west-2a"
    }
    "private-subnet-2b" = {
      cidr = "10.0.4.0/24"
      az   = "eu-west-2b"
    }
  }
}

