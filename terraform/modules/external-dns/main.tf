## External DNS
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
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
  }
}



resource "kubectl_manifest" "external_dns_namespace" {
  yaml_body = <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: external-dns
EOF
}

resource "aws_iam_role" "external_dns" {
  name = var.external_dns_rolename

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(var.oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:external-dns:external-dns",
            "${replace(var.oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "external_dns_route53" {
  name = var.external_dns_policy_name
  role = aws_iam_role.external_dns.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets"
        ]
        Resource = "arn:aws:route53:::hostedzone/*"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets"
        ]
        Resource = "*"
      }
    ]
  })
}


resource "kubernetes_service_account_v1" "external_dns" {
  metadata {
    name      = var.external_dns_name
    namespace = var.external_dns_ns
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.external_dns.arn
    }
  }
  depends_on = [kubectl_manifest.external_dns_namespace]
}



resource "helm_release" "external_dns" {
  name             = var.external_dns_name
  namespace        = var.external_dns_ns
  create_namespace = false
  repository       = "https://kubernetes-sigs.github.io/external-dns/"
  chart            = "external-dns"
  version          = "1.14.0"

  wait    = true
  timeout = 600

  set {
    name  = "provider"
    value = "aws"
  }

  set {
    name  = "aws.region"
    value = "eu-west-2"
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }
  set {
    name  = "serviceAccount.name"
    value = "external-dns"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.external_dns.arn
  }


  depends_on = [
    kubectl_manifest.external_dns_namespace,
    kubernetes_service_account_v1.external_dns,
    aws_iam_role.external_dns,
    aws_iam_role_policy.external_dns_route53
  ]
}

