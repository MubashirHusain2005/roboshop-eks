variable "cluster_endpoint" {
  type = string
}

variable "letsencrypt_staging_name" {
  type = string
}

variable "secrets" {
  default = {
    DB_USER       = "shipping"
    DB_PASSWORD   = "secret"
    root_password = "rootpass"
    user_password = "secret"
    RABBITMQ_USER = "guest"
    RABBITMQ_PASSWORD = "guest"

  }

  type = map(string)
}


variable "oidc_provider_arn" {
  type = string
}

variable "oidc_issuer_url" {
  type = string
}

variable "kms_key_id" {
  type = string
}