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

resource "aws_security_group" "eks-cluster" {
  name        = "cluster-sg"
  description = "Controls who can talk to the EKS Control Plane"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name                                     = "cluster-sg"
    "kubernetes.io/cluster${var.cluster_id}" = "owned"
  }
}

resource "aws_security_group" "nodes" {
  name        = "node-sg"
  description = "Allow nodes to communicate with each other on all ports"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allows node to node communication"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


  ingress {
    description = "Allow SSH traffic from VPC only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]

  }

  tags = {
    Name                                     = "node-sg"
    "karpenter.sh/discovery"                 = var.cluster_id
    "kubernetes.io/cluster${var.cluster_id}" = "owned"
  }

}


resource "aws_security_group_rule" "cluster_ingress_from_nodes" {
  description              = "Allow nodes to communicate with cluster"
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.nodes.id
  security_group_id        = aws_security_group.eks-cluster.id

}

resource "aws_security_group_rule" "node_ingress_from_cluster" {
  description              = "Allow cluster to communicate with nodes"
  type                     = "ingress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks-cluster.id
  security_group_id        = aws_security_group.nodes.id

}


resource "aws_security_group_rule" "node_ingress_webhook" {
  description              = "Allow cluster to reach node webhooks"
  type                     = "ingress"
  from_port                = 8443
  to_port                  = 8443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks-cluster.id
  security_group_id        = aws_security_group.nodes.id
}


resource "aws_security_group_rule" "karpenter_nodes_to_cluster" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.nodes.id
  security_group_id        = var.cluster_security_group_id
  description              = "Allow Karpenter nodes to reach EKS API"
}