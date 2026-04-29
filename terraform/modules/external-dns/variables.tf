variable "oidc_issuer_url" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "external_dns_policy_name" {
  type = string
}

variable "external_dns_name" {
  type = string
}

variable "external_dns_ns" {
  type = string
}

variable "external_dns_rolename" {
  type = string
}

variable "private_node_1_name" {
  type = string
}

variable "private_node_2_name" {
  type = string
}

variable "external_dns_values_file" {
  description = "Path to the Helm values YAML file for external-dns"
  type        = string
}

variable "bucket" {
  description = "Bucket Name"
  default = "terraformstatebucket00534353432534523"
}