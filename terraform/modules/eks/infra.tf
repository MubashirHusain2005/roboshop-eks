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


#EKS AWS authentication,AWS IAM trusts identity tokens issued by my EKS cluster


data "aws_eks_cluster" "eks" {
  name       = aws_eks_cluster.eks_cluster.name
  depends_on = [aws_eks_cluster.eks_cluster]
}

data "tls_certificate" "eks" {
  url = data.aws_eks_cluster.eks.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = data.aws_eks_cluster.eks.identity[0].oidc[0].issuer
}

#EKS 

resource "aws_eks_cluster" "eks_cluster" {
  name    = var.cluster_name
  version = var.clus_vers

  role_arn = var.iam_cluster_role_arn

  # Controls how Kubernetes API authentication works
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }


  # Tells EKS which subnets to use for control-plane ENIs
  vpc_config {
    subnet_ids = [
      var.priv_subnet2a_id,
      var.priv_subnet2b_id
    ]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  encryption_config {
    provider {
      key_arn = var.kms_key_arn
    }
    resources = ["secrets"]
  }

  tags = {
    Environment = "labs"
    Project     = "eks-assignment"
  }


  depends_on = [
    var.iam_cluster_role_arn
  ]
}

#Kubernetes addons which dont require IRSA

resource "aws_eks_addon" "kube-proxy" {
  cluster_name                = aws_eks_cluster.eks_cluster.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_update = "OVERWRITE"

}

resource "aws_eks_addon" "metrics_server" {
  cluster_name                = aws_eks_cluster.eks_cluster.name
  addon_name                  = "metrics-server"
  resolve_conflicts_on_update = "OVERWRITE"

}

##Kubernetes addons which do require IRSA


##EBS CSI Driver 

resource "aws_iam_role" "ebs_csi_driver" {
  name = "ebs-csi-driver"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "${aws_iam_openid_connect_provider.eks.arn}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa",
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver_attach" {
  role       = aws_iam_role.ebs_csi_driver.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}



resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name                = aws_eks_cluster.eks_cluster.name
  addon_name                  = "aws-ebs-csi-driver"
  resolve_conflicts_on_update = "OVERWRITE"
  resolve_conflicts_on_create = "OVERWRITE"
  configuration_values        = null
  preserve                    = true
  service_account_role_arn    = aws_iam_role.ebs_csi_driver.arn

  depends_on = [
    aws_iam_openid_connect_provider.eks,
    aws_iam_role_policy_attachment.ebs_csi_driver_attach,
    aws_eks_node_group.private_node_1,
    aws_eks_node_group.private_node_2
  ]

}

##VPC CNI add-on

resource "aws_iam_role" "vpc_cni" {
  name = "vpc_cni"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "${aws_iam_openid_connect_provider.eks.arn}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-node",
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "vpc_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.vpc_cni.name
}



resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.eks_cluster.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_update = "OVERWRITE"
  resolve_conflicts_on_create = "OVERWRITE"
  configuration_values        = null
  preserve                    = true
  service_account_role_arn    = aws_iam_role.vpc_cni.arn

  depends_on = [
    aws_iam_openid_connect_provider.eks,
    aws_iam_role_policy_attachment.vpc_cni_policy,
    aws_eks_node_group.private_node_1,
    aws_eks_node_group.private_node_2

  ]

}

##Node Group 1
resource "aws_eks_node_group" "private_node_1" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_role_arn   = var.nodegroup_role_arn
  node_group_name = var.node_group_name

  subnet_ids = [
    var.priv_subnet2a_id,
    var.priv_subnet2b_id
  ]

  capacity_type  = "ON_DEMAND"
  instance_types = ["t3.large"]

  scaling_config {
    desired_size = 2 ###This was 2
    max_size     = 3
    min_size     = 1
  }

  labels = {
    workload = "app" ##Label for  Node affinity
  }


  update_config {
    max_unavailable = 1
  }


  tags = {
    "kubernetes.io/cluster/${aws_eks_cluster.eks_cluster.name}" = "owned"
  }



  depends_on = [var.nodegroup_role_arn]

}

##Node Group 2
resource "aws_eks_node_group" "private_node_2" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_role_arn   = var.nodegroup_role_arn
  node_group_name = var.node_group_name_2

  subnet_ids = [
    var.priv_subnet2a_id,
    var.priv_subnet2b_id
  ]

  capacity_type  = "ON_DEMAND"
  instance_types = ["t3.large"]

  scaling_config {
    desired_size = 2 ##This was 2 
    max_size     = 3
    min_size     = 1
  }

  labels = {
    workload = "app"
  }


  update_config {
    max_unavailable = 1
  }


  tags = {
    "kubernetes.io/cluster/${aws_eks_cluster.eks_cluster.name}" = "owned"
  }


  depends_on = [var.nodegroup_role_arn]

}


