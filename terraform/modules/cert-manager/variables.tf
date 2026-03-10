variable "create_namespace" {
  type    = bool
  default = true
}

variable "cert_issuer" {
  description = "Which lets encrypt clusterissuer to use"
  type        = string
  default     = "letsencrypt-prod"

}

variable "cluster_endpoint" {
  type = string
}


variable "private_node_1_name" {
  type = string
}

variable "private_node_2_name" {
  type = string
}

variable "cert_manager_values_file" {
  description = "Path to the cert-manager values.yaml file"
  type        = string

}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_issuer_url" {
  type = string
}