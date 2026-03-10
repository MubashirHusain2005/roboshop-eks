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


resource "kubectl_manifest" "deployments_namespace" {
  yaml_body = <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: app-space
  labels:
    istio-injection: enabled
EOF

  depends_on = [var.cluster_endpoint]
}

resource "kubectl_manifest" "databases_namespace" {
  yaml_body  = <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: data-space
EOF
  depends_on = [var.cluster_endpoint]
}

resource "kubectl_manifest" "external_secrets_namespace" {
  yaml_body = <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: external-secrets
EOF

  depends_on = [var.cluster_endpoint]
}



##Creates the container to store secrets
resource "aws_secretsmanager_secret" "secrets" {
  name = "db-creds"
}


##Actually stores the secret value
resource "aws_secretsmanager_secret_version" "secrets" {
  secret_id     = aws_secretsmanager_secret.secrets.id
  secret_string = jsonencode(var.secrets)
}


##ESO via Helm Chart
resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  namespace  = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = "0.14.0"

  values = [
    templatefile("${path.root}/${var.external_secrets_values_file}", {})
  ]


  depends_on = [kubernetes_service_account_v1.eso_serviceaact]

}

##IAM Role for eso controller
resource "aws_iam_role" "iam_role_eso" {
  name = "iamrole-eso"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "${var.oidc_provider_arn}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(var.oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:external-secrets:eso-sa",
            "${replace(var.oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}


resource "aws_iam_policy" "iam_eso_policy" {
  name = "iampolicy-eso"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecrets",
          "secretsmanager:GetResourcePolicy"
        ]
        Resource = "*"
      },
    ]
  })
}


resource "aws_iam_role_policy_attachment" "iampolicyattach-eso" {
  role       = aws_iam_role.iam_role_eso.name
  policy_arn = aws_iam_policy.iam_eso_policy.arn
}


##Service Account for the shipping pod 

resource "kubernetes_service_account_v1" "eso_serviceaact" {
  metadata {
    name      = "eso-sa"
    namespace = "external-secrets"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.iam_role_eso.arn
    }
  }
  depends_on = [
    aws_iam_role_policy_attachment.iampolicyattach-eso,
    kubectl_manifest.external_secrets_namespace,
  ]
}

##Reference to AWS Secrets Manager and tells k8s where to fetch secrets
resource "kubectl_manifest" "cluster_secret_store" {
  yaml_body = <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: secretstore
spec:
  provider:
    aws:
      service: SecretsManager
      region: eu-west-2
      auth:
        jwt:
          serviceAccountRef:
            name: eso-sa
            namespace: external-secrets
EOF

  depends_on = [
    kubernetes_service_account_v1.eso_serviceaact,
    aws_secretsmanager_secret_version.secrets,
    aws_secretsmanager_secret.secrets,
    helm_release.external_secrets
  ]
}


##Secret to fetch from AWS Secrets Manager and create a k8s secret so shipping pod can authenticate with mysql
resource "kubectl_manifest" "external_secret" {
  yaml_body = <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: shipping-db-secret
  namespace: app-space
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: secretstore
    kind: ClusterSecretStore
  target:
    name: mysql-secret
  data:
    - secretKey: DB_USER
      remoteRef:
        key: db-creds
        property: DB_USER
    - secretKey: DB_PASSWORD
      remoteRef:
        key: db-creds
        property: DB_PASSWORD
    - secretKey: root-password
      remoteRef:
        key: db-creds
        property: root-password
    - secretKey: user-password
      remoteRef:
        key: db-creds
        property: user-password
EOF

  depends_on = [
    kubectl_manifest.cluster_secret_store,
  ]
}

####Secret to fetch from AWS Secrets Manager and create a k8s secret so mysql-exporter can authenticate with mysql

#resource "kubectl_manifest" "external_secret_mysql" {
# yaml_body = <<EOF
#apiVersion: external-secrets.io/v1beta1
#kind: ExternalSecret
#metadata:
# name: shipping-db-secret
#namespace: monitoring
#spec:
# refreshInterval: 1h
# secretStoreRef:
# name: secretstore
# kind: ClusterSecretStore
# target:
# name: kube-secret
#  data:
#  - secretKey: DB_USER
# remoteRef:
#  key: db-creds
# property: DB_USER
# - secretKey: DB_PASSWORD
#  remoteRef:
# key: db-creds
#property: DB_PASSWORD
#EOF

# depends_on = [
#kubectl_manifest.cluster_secret_store
# ]
#}





