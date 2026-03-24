
variable "cluster_endpoint" {
  type = string
}

variable "private_node_1_name" {
  type = string
}

variable "private_node_2_name" {
  type = string
}

variable "prometheus_values_file" {
  type        = string
  description = "Path to Prometheus Helm values file (from root where terraform is run)"
}

variable "prometheus_secret_name" {
  type    = string
  default = "prometheus-db-creds"
}

##Grafana

variable "cluster_name" {
  type = string
}

variable "monitoring_namespace" {
  description = "Namespace to deploy observability charts"
  type        = string
  default     = "monitoring"
}

