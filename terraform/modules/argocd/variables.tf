variable "cluster_name" {
  type = string
}


variable "private_node_1_name" {
  type = string
}

variable "private_node_2_name" {
  type = string
}

variable "app_secrets" {
  type      = string
  default   = "db-creds"
  sensitive = true
}
