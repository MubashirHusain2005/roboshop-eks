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
