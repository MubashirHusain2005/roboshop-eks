provider "aws" {
  region = "eu-west-2"
}


##S3 Bucket to store tf state file

resource "aws_s3_bucket" "terraform_state_bucket" {
  bucket = "terraformstatebucket00534353432534523"

  lifecycle {
    prevent_destroy = false
  }

  tags = {
    Name        = "My bucket"
    Description = "Storage for Terraform State"
  }
}

##Enabled Versioning

resource "aws_s3_bucket_versioning" "s3_versioning" {
  bucket = aws_s3_bucket.terraform_state_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

## Enable encryption 

resource "aws_s3_bucket_server_side_encryption_configuration" "s3_encryption" {
  bucket = aws_s3_bucket.terraform_state_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

##Block All public access- state files should never be public

resource "aws_s3_bucket_public_access_block" "terraform_s3_access" {
  bucket = aws_s3_bucket.terraform_state_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

##Bucket policy enforces SSL/TLS connectiosn only 
resource "aws_s3_bucket_policy" "s3_bucket_policy" {
  bucket = aws_s3_bucket.terraform_state_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnforceTLS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          "${aws_s3_bucket.terraform_state_bucket.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

##DynamoDB for Statelock

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "state-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"


  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name        = "terraform-lock"
    description = "Terraform State lock for EKS"
  }
}


#OIDC for github actions

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

resource "aws_iam_role_policy_attachment" "oidc_s3_access" {
  role       = aws_iam_role.github_oidc_role.name
  policy_arn = aws_iam_policy.oidc_access_aws.arn
}


#IAM Role for ECR

resource "aws_iam_role" "ecr_role" {
  name = "ecr"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}


resource "aws_iam_policy" "ecr_policy" {
  name = "ecr-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:DescribeImages",
          "ecr:DescribeRepositories",
          "ecr:CompleteLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:InitiateLayerUpload",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:BatchGetImage",
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecr_policy" {
  policy_arn = aws_iam_policy.ecr_policy.arn
  role       = aws_iam_role.ecr_role.id
}


# ECR to store my Cart Docker image
resource "aws_ecr_repository" "cart" {
  name                 = var.cart
  image_tag_mutability = var.image_tag_mutability

  # Scan images for vulnerabilities on push
  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  # Encryption at rest
  encryption_configuration {
    encryption_type = "AES256"
  }

}

##ECR lifecycle policy to clean up old images to save on storage costs

resource "aws_ecr_lifecycle_policy" "ecr_policy_cart" {
  repository = aws_ecr_repository.cart.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only 12 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 12
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}


#ECR to store my catalogue Docker image
resource "aws_ecr_repository" "catalogue" {
  name                 = var.catalogue
  image_tag_mutability = var.image_tag_mutability

  # Scan images for vulnerabilities on push
  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  # Encryption at rest
  encryption_configuration {
    encryption_type = "AES256"
  }

}

##ECR lifecycle policy to clean up old images to save on storage costs

resource "aws_ecr_lifecycle_policy" "ecr_policy_catalogue" {
  repository = aws_ecr_repository.catalogue.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only 12 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 12
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}


#ECR to store my dispatch Docker image
resource "aws_ecr_repository" "dispatch" {
  name                 = var.dispatch
  image_tag_mutability = var.image_tag_mutability

  # Scan images for vulnerabilities on push
  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  # Encryption at rest
  encryption_configuration {
    encryption_type = "AES256"
  }

}

##ECR lifecycle policy to clean up old images to save on storage costs

resource "aws_ecr_lifecycle_policy" "ecr_policy_dispatch" {
  repository = aws_ecr_repository.dispatch.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only 12 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 12
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}


#ECR to store my fluentd Docker image
resource "aws_ecr_repository" "fluentd" {
  name                 = var.fluentd
  image_tag_mutability = var.image_tag_mutability

  # Scan images for vulnerabilities on push
  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  # Encryption at rest
  encryption_configuration {
    encryption_type = "AES256"
  }

}

##ECR lifecycle policy to clean up old images to save on storage costs

resource "aws_ecr_lifecycle_policy" "ecr_policy_fluentd" {
  repository = aws_ecr_repository.fluentd.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only 12 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 12
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}


#ECR to store my load-gen Docker image
resource "aws_ecr_repository" "loadgen" {
  name                 = var.loadgen
  image_tag_mutability = var.image_tag_mutability

  # Scan images for vulnerabilities on push
  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  # Encryption at rest
  encryption_configuration {
    encryption_type = "AES256"
  }

}

##ECR lifecycle policy to clean up old images to save on storage costs

resource "aws_ecr_lifecycle_policy" "ecr_policy_loadgen" {
  repository = aws_ecr_repository.loadgen.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only 12 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 12
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}


#ECR to store my mongo Docker image
resource "aws_ecr_repository" "mongo" {
  name                 = var.mongo
  image_tag_mutability = var.image_tag_mutability

  # Scan images for vulnerabilities on push
  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  # Encryption at rest
  encryption_configuration {
    encryption_type = "AES256"
  }

}

##ECR lifecycle policy to clean up old images to save on storage costs

resource "aws_ecr_lifecycle_policy" "ecr_policy_mongo" {
  repository = aws_ecr_repository.mongo.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only 12 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 12
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}


#ECR to store my mysql Docker image
resource "aws_ecr_repository" "mysql" {
  name                 = var.mysql
  image_tag_mutability = var.image_tag_mutability

  # Scan images for vulnerabilities on push
  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  # Encryption at rest
  encryption_configuration {
    encryption_type = "AES256"
  }

}

##ECR lifecycle policy to clean up old images to save on storage costs

resource "aws_ecr_lifecycle_policy" "ecr_policy_mysql" {
  repository = aws_ecr_repository.mysql.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only 12 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 12
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}


#ECR to store my payment Docker image
resource "aws_ecr_repository" "payment" {
  name                 = var.payment
  image_tag_mutability = var.image_tag_mutability

  # Scan images for vulnerabilities on push
  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  # Encryption at rest
  encryption_configuration {
    encryption_type = "AES256"
  }

}

##ECR lifecycle policy to clean up old images to save on storage costs

resource "aws_ecr_lifecycle_policy" "ecr_policy_payment" {
  repository = aws_ecr_repository.payment.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only 12 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 12
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}


#ECR to store my ratings Docker image
resource "aws_ecr_repository" "ratings" {
  name                 = var.ratings
  image_tag_mutability = var.image_tag_mutability

  # Scan images for vulnerabilities on push
  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  # Encryption at rest
  encryption_configuration {
    encryption_type = "AES256"
  }

}

##ECR lifecycle policy to clean up old images to save on storage costs

resource "aws_ecr_lifecycle_policy" "ecr_policy_ratings" {
  repository = aws_ecr_repository.ratings.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only 12 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 12
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

#ECR to store my shipping Docker image
resource "aws_ecr_repository" "shipping" {
  name                 = var.shipping
  image_tag_mutability = var.image_tag_mutability

  # Scan images for vulnerabilities on push
  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  # Encryption at rest
  encryption_configuration {
    encryption_type = "AES256"
  }

}

##ECR lifecycle policy to clean up old images to save on storage costs

resource "aws_ecr_lifecycle_policy" "ecr_policy_shipping" {
  repository = aws_ecr_repository.shipping.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only 12 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 12
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}


#ECR to store my user Docker image
resource "aws_ecr_repository" "user" {
  name                 = var.user
  image_tag_mutability = var.image_tag_mutability

  # Scan images for vulnerabilities on push
  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  # Encryption at rest
  encryption_configuration {
    encryption_type = "AES256"
  }

}

##ECR lifecycle policy to clean up old images to save on storage costs

resource "aws_ecr_lifecycle_policy" "ecr_policy_user" {
  repository = aws_ecr_repository.user.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only 12 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 12
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}


#ECR to store my web Docker image
resource "aws_ecr_repository" "web" {
  name                 = var.web
  image_tag_mutability = var.image_tag_mutability

  # Scan images for vulnerabilities on push
  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  # Encryption at rest
  encryption_configuration {
    encryption_type = "AES256"
  }

}

##ECR lifecycle policy to clean up old images to save on storage costs

resource "aws_ecr_lifecycle_policy" "ecr_policy_web" {
  repository = aws_ecr_repository.web.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only 12 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 12
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}


