##Github Actions OIDC Role

data "aws_iam_role" "github_oidc_role" {
    name = "github.to.aws.oidc"
}

#resource "aws_eks_access_entry" "github_role" {
  #cluster_name      = var.cluster_name
 # principal_arn     = data.aws_iam_role.github_oidc_role.arn
  #kubernetes_groups = ["dev:admins"]
  #type              = "STANDARD"
#}

##My IAM User

data "aws_iam_user" "terraform_user" {
    user_name = "terraform-test"
}

resource "aws_eks_access_entry" "terraform_user" {
  cluster_name      = var.cluster_name
  principal_arn     = data.aws_iam_user.terraform_user.arn
  kubernetes_groups = ["dev-admins"]  
  type              = "STANDARD"
}

###RBAC

resource "kubectl_manifest" "rbac" {
    yaml_body = <<EOF

apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: github-admin-binding
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