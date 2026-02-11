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
    root-password = "rootpass"
    user-password = "secret"

  }

  type = map(string)
}


variable "oidc_provider_arn" {
  type = string
}

variable "oidc_issuer_url" {
  type = string
}

