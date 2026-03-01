variable "cluster_name" {
  type = string
}

variable "monitoring_namespace" {
  description = "Namespace to deploy observability charts"
  type        = string
}

variable "prometheus_helmchart" {
  type = string
}

variable "private_node_1_name" {
  type = string
}

variable "private_node_2_name" {
  type = string
}