variable "cluster_name" {
  type = string
}

variable "helm_release_nginx" {
  type = string
}

variable "pass" {
  type    = string
  default = "$2a$10$vET5C80SWoSIGrXbZpu9O.WK86Oc0daZhABC1an7/XT2atvEwlGx2"
}

variable "private_node_1_name" {
  type = string
}

variable "private_node_2_name" {
  type = string
}