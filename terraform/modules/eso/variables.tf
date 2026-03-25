
variable "cluster_endpoint" {
  type = string
}

variable "oidc_issuer_url" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "private_node_1_name" {
  type = string
}

variable "private_node_2_name" {
  type = string
}

variable "external_secrets_values_file" {
  description = "Path to the external-secrets Helm values.yaml file"
  type        = string

}

variable "kms_key_id" {
  type = string
}

variable "apps_secrets" {
  type      = string
  default   = "db-creds"
  sensitive = true
}

variable "monitoring_secrets" {
  type      = string
  default   = "prometheus-db-creds"
  sensitive = true
}