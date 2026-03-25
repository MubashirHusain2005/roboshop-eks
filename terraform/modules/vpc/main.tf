terraform {
  required_providers {

    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.2.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12.0"
    }


    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.7.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

data "aws_caller_identity" "current" {}

#KMS encryption used later for EKS Cluster encryption

resource "aws_kms_key" "kms_key" {
  description             = "Encryption KMS key"
  enable_key_rotation     = true
  deletion_window_in_days = 20
}


resource "aws_kms_alias" "kms_alias" {
  name          = "alias/newkey"
  target_key_id = aws_kms_key.kms_key.id

}


resource "aws_kms_key_policy" "kms_key_policy" {
  key_id = aws_kms_key.kms_key.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"

        Principal = {
          AWS = "arn:aws:iam::038774803581:root"
        }

        Action   = "kms:*"
        Resource = "*"
      },

      {
        Sid    = "AllowCloudWatchLogsUseOfKey"
        Effect = "Allow"

        Principal = {
          Service = "logs.eu-west-2.amazonaws.com"
        }

        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ]

        Resource = "*"
      },
      {
        Sid    = "AllowEKSUseOfKey"
        Effect = "Allow"

        Principal = {
          Service = "eks.amazonaws.com"
        }

        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],

        Resource = "*"
      },
    ]
  })
}


resource "aws_vpc" "eks_vpc" {
  cidr_block           = var.vpc_cidr
  instance_tenancy     = var.inst_tenancy
  enable_dns_hostnames = var.enable_host
  enable_dns_support   = var.enable_support

  tags = {
    Name = "Main-VPC"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.eks_vpc.id

  tags = {
    Name = "IGW"
  }

  depends_on = [aws_vpc.eks_vpc]
}

resource "aws_subnet" "public" {
  for_each                = var.public_subnets
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = {
    Name                                        = each.key
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  depends_on = [aws_vpc.eks_vpc]

  lifecycle {
    prevent_destroy = false
    ignore_changes  = [tags]
  }
}

resource "aws_route_table" "public-rt" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-rt"
  }

  depends_on = [aws_vpc.eks_vpc, aws_internet_gateway.igw]
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public-rt.id
}

resource "aws_subnet" "private" {
  for_each                = var.private_subnets
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false

  tags = {
    Name                                        = each.key
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "karpenter.sh/discovery"                    = var.cluster_name
  }

  depends_on = [aws_vpc.eks_vpc]

  lifecycle {
    prevent_destroy = false
    ignore_changes  = [tags]
  }
}

#resource "aws_route_table_association" "private" {
#for_each       = aws_subnet.private
#subnet_id      = each.value.id
#route_table_id = aws_route_table.private-rt.id
#}


#resource "aws_eip" "ngw-eip" {
#domain = "vpc"

#tags = {
#Name = "eip"
#}

#}

resource "aws_eip" "ngw_eip" {
  for_each = var.public_subnets

  domain = "vpc"

  tags = {
    Name = "nat-eip-${each.value.az}"
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_nat_gateway" "ngw" {
  for_each = var.public_subnets

  subnet_id     = aws_subnet.public[each.key].id
  allocation_id = aws_eip.ngw_eip[each.key].id

  tags = {
    Name = "nat-${each.value.az}"
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "private" {
  for_each = var.private_subnets

  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ngw[[
      for key, subnet in var.public_subnets :
      key if subnet.az == each.value.az
    ][0]].id
  }

  tags = {
    Name = "rt-private-${each.key}"
  }

  depends_on = [aws_nat_gateway.ngw]
}

resource "aws_route_table_association" "private" {
  for_each = var.private_subnets

  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}

#resource "aws_nat_gateway" "ngw" {
#subnet_id     = aws_subnet.public["public-subnet-2b"].id
#allocation_id = aws_eip.ngw-eip.id

# tags = {
# Name = "igw-nat"
#}

# depends_on = [aws_internet_gateway.igw, aws_eip.ngw-eip]
#}



#resource "aws_route_table" "private-rt" {
#vpc_id = aws_vpc.eks_vpc.id

#route {
#cidr_block     = "0.0.0.0/0"
#nat_gateway_id = aws_nat_gateway.ngw.id
# }

# tags = {
# Name = "private-rt"

#}

#depends_on = [aws_nat_gateway.ngw]

#}

#resource "aws_route_table_association" "private-route-association-2a" {

#route_table_id = aws_route_table.private-rt.id
#subnet_id      = aws_subnet.public["private-subnet-2a"].id
#}

#resource "aws_route_table_association" "private-route-association-2b" {
#route_table_id = aws_route_table.private-rt.id
#subnet_id      = aws_subnet.public["private-subnet-2b"].id
#}


###CloudWatch for VPC logs

resource "aws_flow_log" "cloud_watch" {
  iam_role_arn    = var.vpc_flow_logs_role
  log_destination = aws_cloudwatch_log_group.cloud_watch_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.eks_vpc.id
}

#Stores the log streams
resource "aws_cloudwatch_log_group" "cloud_watch_logs" {
  name              = "logs_for_cloudwatch"
  retention_in_days = 7
  kms_key_id        = aws_kms_key.kms_key.arn
}

