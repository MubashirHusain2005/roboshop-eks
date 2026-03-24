## External DNS
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

data "aws_s3_bucket" "s3_bucket" {
  bucket = "terraformstatebucket00534353432534523"
}


data "aws_route53_zone" "hosted_zone" {
  name         = "mubashir.site"
  private_zone = false
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
        Resource = "arn:aws:route53:::hostedzone/Z09331692XTWCNAOSXR5T"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets"
        ]
        Resource = "arn:aws:route53:::hostedzone/Z09331692XTWCNAOSXR5T"
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
  force_update     = true
  recreate_pods    = true
  cleanup_on_fail = true


  wait    = true
  timeout = 600

  values = [templatefile(var.external_dns_values_file, {
    role_arn = aws_iam_role.external_dns.arn
  })]


  depends_on = [
    kubectl_manifest.external_dns_namespace,
    kubernetes_service_account_v1.external_dns,
    aws_iam_role.external_dns,
    aws_iam_role_policy.external_dns_route53,
    kubectl_manifest.externaldns_rbac,
    kubectl_manifest.externaldns_cluster_role_binding,
  ]
}

##RBAC RULE to allow External-dns to read gateways and services


##The cluster role is the set of permissions of what can be done
resource "kubectl_manifest" "externaldns_rbac" {
  yaml_body = <<EOF

apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: external-dns
rules:
- apiGroups: ["networking.istio.io"]
  resources: ["gateways"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["networking.istio.io"]
  resources: ["virtualservices"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["services"]
  verbs: ["get", "list", "watch"]
EOF
}


#Clusterrolebinding is who gets those permissions serviceaccount/user
resource "kubectl_manifest" "externaldns_cluster_role_binding" {
  yaml_body = <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: external-dns
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: external-dns
subjects:
- kind: ServiceAccount
  name: external-dns
  namespace: external-dns
EOF

  depends_on = [
    kubectl_manifest.externaldns_rbac,
    kubernetes_service_account_v1.external_dns
  ]
}

##CloudTrail to monitor Route53 activity/auditing

resource "aws_cloudtrail" "route_53_access" {
  name                          = "route53-access-monitoring"
  s3_bucket_name                = data.aws_s3_bucket.s3_bucket.id
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true

  }

  depends_on = [data.aws_s3_bucket.s3_bucket]
}