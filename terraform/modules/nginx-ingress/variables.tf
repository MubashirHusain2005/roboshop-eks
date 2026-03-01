variable "cluster_endpoint" {
  type = string
}

variable "private_node_1_name" {
  type = string
}

variable "private_node_2_name" {
  type = string
}

variable "nginx_values_file" {
  description = "Path to the Helm values YAML file for nginx-ingress"
  type        = string
}