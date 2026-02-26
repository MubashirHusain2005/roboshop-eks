variable "cluster_name" {
  type = string
}

variable "monitoring_namespace" {
  type    = string
  default = "monitoring"
}

variable "cluster_endpoint" {
  type = string
}