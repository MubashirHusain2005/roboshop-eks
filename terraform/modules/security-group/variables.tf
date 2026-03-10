variable "vpc_id" {
  type = string
}

variable "cluster_id" {
  type = string
}

variable "vpc_cidr_block" {
  type    = string
  default = "10.0.0.0/16"
}


variable "cluster_security_group_id" {
  type        = string
  description = "The EKS managed cluster security group ID"
}