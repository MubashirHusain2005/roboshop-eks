# GitHub Actions OIDC Role
#data "aws_iam_role" "github_oidc_role" {
#name = "github.to.aws.oidc"
#}

#resource "aws_eks_access_entry" "github_role" {
#cluster_name      = aws_eks_cluster.eks_cluster.name
#principal_arn     = data.aws_iam_role.github_oidc_role.arn
#kubernetes_groups = ["dev-admins"]
#type              = "STANDARD"
#}

#resource "aws_eks_access_policy_association" "github_role_admin" {
#cluster_name  = var.cluster_name
# principal_arn = data.aws_iam_role.github_oidc_role.arn
#policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

#access_scope {
#type = "cluster"
# }

#depends_on = [aws_eks_access_entry.github_role]
#}

# Terraform IAM User
#data "aws_iam_user" "terraform_user" {
#user_name = "terraform-test"
#}

#resource "aws_eks_access_entry" "terraform_user" {
#cluster_name      = var.cluster_name
#principal_arn     = data.aws_iam_user.terraform_user.arn
 #kubernetes_groups = ["dev-admins"]
#type              = "STANDARD"
#}

###In production I would not want to give cluster admin policy
#resource "aws_eks_access_policy_association" "terraform_user_admin" {
#cluster_name  = var.cluster_name
#principal_arn = data.aws_iam_user.terraform_user.arn
#policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

#access_scope {
 #type = "cluster"
#}

#depends_on = [aws_eks_access_entry.terraform_user]
#}

# RBAC
resource "kubectl_manifest" "rbac" {
  yaml_body = <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: dev-admin-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: Group
  name: dev-admins
  apiGroup: rbac.authorization.k8s.io
EOF

  depends_on = [aws_eks_cluster.eks_cluster]
}






###Create a config map called auth

