###VPC Networking
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

##This needs looking at because I cant attach it to the irsa role when it hasnt even been created.
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

resource "aws_subnet" "public-subnet-2a" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = var.pub_cidr_2a
  availability_zone       = var.avai_zone_2a
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "Public-subnet-2a"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}


resource "aws_subnet" "public-subnet-2b" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = var.pub_cidr_2b
  availability_zone       = var.avai_zone_2b
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "Public-subnet-2b"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}



resource "aws_route_table" "public-rt" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
  Name = "public-rt" }

  depends_on = [aws_vpc.eks_vpc, aws_internet_gateway.igw]
}



resource "aws_route_table_association" "pub-route-association-2a" {

  route_table_id = aws_route_table.public-rt.id
  subnet_id      = aws_subnet.public-subnet-2a.id

}

resource "aws_route_table_association" "pub-route-association-2b" {
  route_table_id = aws_route_table.public-rt.id
  subnet_id      = aws_subnet.public-subnet-2b.id
}



resource "aws_subnet" "private-subnet-2a" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = var.priv_cidr_2c
  availability_zone       = var.avai_zone_2a
  map_public_ip_on_launch = false

  tags = {
    Name                                        = "Private-subnet-2a"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "karpenter.sh/discovery"                    = var.cluster_name
  }
}

resource "aws_subnet" "private-subnet-2b" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = var.priv_cidr_2d
  availability_zone       = var.avai_zone_2b
  map_public_ip_on_launch = false

  tags = {
    Name                                        = "Private-subnet-2b"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "karpenter.sh/discovery"                    = var.cluster_name
  }
}


resource "aws_eip" "ngw-eip" {
  domain = "vpc"

  tags = {
    Name = "eip"
  }

}

resource "aws_nat_gateway" "ngw" {
  subnet_id     = aws_subnet.public-subnet-2b.id
  allocation_id = aws_eip.ngw-eip.id

  tags = {
    Name = "igw-nat"
  }

  depends_on = [aws_internet_gateway.igw, aws_eip.ngw-eip]
}



resource "aws_route_table" "private-rt" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ngw.id
  }

  tags = {
    Name = "private-rt"

  }

  depends_on = [aws_nat_gateway.ngw]

}

resource "aws_route_table_association" "private-route-association-2a" {

  route_table_id = aws_route_table.private-rt.id
  subnet_id      = aws_subnet.private-subnet-2a.id


}

resource "aws_route_table_association" "private-route-association-2b" {

  route_table_id = aws_route_table.private-rt.id
  subnet_id      = aws_subnet.private-subnet-2b.id

}


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

