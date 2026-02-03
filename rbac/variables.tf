#Frontend Team
variable "enable_rbac" {
  description = "Enable RBAC resources or not "
  type        = bool
}

#Platform Team
variable "enable_platform_rbac" {
  type        = bool
  description = "Enable cluster-wide platform RBAC or not"
}
