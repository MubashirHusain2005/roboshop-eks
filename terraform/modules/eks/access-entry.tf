##Only need on github actions-GitHub Actions OIDC Role

data "aws_eks_cluster" "eks" {
  name       = aws_eks_cluster.eks_cluster.name
  depends_on = [aws_eks_cluster.eks_cluster]
}

data "aws_iam_role" "github_oidc_role" {
  name = "github.to.aws.oidc"
}

data "aws_iam_user" "terraform_user" {
  user_name = "terraform-test"
}

resource "aws_eks_access_entry" "terraform_user" {
  cluster_name      = aws_eks_cluster.eks_cluster.name
  principal_arn     = data.aws_iam_user.terraform_user.arn
  kubernetes_groups = ["dev-admins"]
  type              = "STANDARD"
}


resource "aws_eks_access_policy_association" "terraform_user_admin" {
  cluster_name  = var.cluster_name
  principal_arn = data.aws_iam_user.terraform_user.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.terraform_user]

}




