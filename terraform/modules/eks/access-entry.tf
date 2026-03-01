##Github Actions OIDC Role

data "aws_iam_role" "github_oidc_role" {
    name = "github.to.aws.oidc"
}


resource "aws_eks_access_entry" "github_role" {
  cluster_name      = var.cluster_name
  principal_arn     = data.aws_iam_role.github_oidc_role.arn
  kubernetes_groups = ["system:masters"]
  type              = "STANDARD"
}

##My IAM User

data "aws_iam_user" "terraform_user" {
    user_name = "terraform-test"
}

resource "aws_eks_access_entry" "terraform_user" {
  cluster_name      = var.cluster_name
  principal_arn     = data.aws_iam_user.terraform_user.arn
  kubernetes_groups = ["system:masters"]  
  type              = "STANDARD"
}