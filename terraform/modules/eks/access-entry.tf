resource "aws_eks_access_entry" "terraform_admin" {
  cluster_name  = "eks-cluster"
  principal_arn = "arn:aws:iam::038774803581:role/github.to.aws.oidc"

  lifecycle {
    prevent_destroy = false
  }
  depends_on = [aws_eks_cluster.eks_cluster]

}


resource "aws_eks_access_policy_association" "terraform_admin" {
  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = "arn:aws:iam::038774803581:role/github.to.aws.oidc"
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  lifecycle {
    prevent_destroy = false
  }

  depends_on = [aws_eks_cluster.eks_cluster]

}