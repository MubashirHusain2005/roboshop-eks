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


data "tls_certificate" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
}


resource "aws_iam_openid_connect_provider" "oidc" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github_actions.certificates[0].sha1_fingerprint]
}



resource "aws_iam_role" "github_oidc_role" {
  name = var.oidc_name
  lifecycle {
    prevent_destroy = true
  }
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Federated" = "${aws_iam_openid_connect_provider.oidc.arn}"
        },
        "Action" : "sts:AssumeRoleWithWebIdentity",
        "Condition" : {
          "StringEquals" : {
            "token.actions.githubusercontent.com:aud" : "sts.amazonaws.com"
          },
          "StringLike" : {
            "token.actions.githubusercontent.com:sub" : "repo:MubashirHusain2005/gatus-eks:*"
          }
        }
      },
    ]
  })
}

resource "aws_iam_policy" "oidc_access_aws" {
  name        = "oidc_access_aws"
  path        = "/"
  description = "Policy document to allow OIDC access to AWS resources during CI/CD"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [

      {
        Sid      = "ListStateBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::mhusains3"
      },
      {
        Sid    = "ReadWriteStateObject"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::mhusains3/*"
      },


      {
        Sid    = "DynamoDBTableAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable",
          "dynamodb:UpdateItem"
        ]
        Resource = "arn:aws:dynamodb:eu-west-2:038774803581:table/terraform-lock"
      },

      {
        Sid    = "AccessToKMS"
        Effect = "Allow"
        Action = [
          "kms:CreateKey",
          "kms:DescribeKey",
          "kms:EnableKey",
          "kms:PutKeyPolicy",
          "kms:TagResource",
          "kms:CreateAlias",
          "kms:ScheduleKeyDeletion",
          "kms:EnableKeyRotation",
          "kms:GetKeyPolicy",
          "kms:GetKeyRotationStatus",
          "kms:ListResourceTags",
          "kms:ListAliases",
          "kms:DeleteAlias",
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*",
          "kms:CreateGrant"
        ]
        Resource = "*"
      },


      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutRetentionPolicy",
          "logs:ListTagsForResource",
          "logs:DeleteLogGroup",
          "logs:DeleteRetentionPolicy"
        ]
        Resource = "*"
      },

      {
        Sid    = "SecretsManager"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:DeleteSecret"
        ]
      },


      {
        Sid    = "EKS"
        Effect = "Allow"
        Action = [
          "autoscaling:CreateAutoScalingGroup",
          "autoscaling:UpdateAutoScalingGroup",
          "autoscaling:DeleteAutoScalingGroup",
          "autoscaling:DescribeAutoScalingGroups",
          "eks:CreateCluster",
          "eks:TagResource",
          "eks:DescribeCluster",
          "eks:DeleteCluster",
          "eks:CreateNodegroup",
          "eks:DeleteNodegroup",
          "eks:DescribeNodegroup",
          "eks:CreateAddon",
          "eks:DescribeAddon",
          "eks:ListAddon",
          "eks:DescribeAddonVersion",
          "eks:DeleteAddon"
        ]
        Resource = "*"
      },


      {
        Sid    = "ElasticLoadBalancing"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DeleteLoadBalancer"
        ]
        Resource = "*"
      }
    ]
  })
}
