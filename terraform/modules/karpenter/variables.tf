variable "oidc_issuer_url" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "cluster_id" {
  type = string
}


variable "private_node_1_name" {
  type = string
}

variable "private_node_2_name" {
  type = string
}

variable "node_instance_profile" {
  type = string
}

variable "karpenter_values_file" {
  type = string
}

variable "cluster_endpoint" {
  type = string
}