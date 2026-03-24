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

##Calls existing secret store from AWS
data "aws_secretsmanager_secret" "secrets" {
  name = var.secret_name
}

data "aws_secretsmanager_secret" "prometheus_secrets" {
  name = var.secret_name
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

resource "kubectl_manifest" "monitoring_namespace" {
  yaml_body = <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
EOF

  depends_on = [var.cluster_endpoint]
}


##ESO Helm Chart
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
        Resource = [
          "arn:aws:secretsmanager:eu-west-2:038774803581:secret:db-creds-*",           #this was just * before making it specifc to my secret on AWS
          "arn:aws:secretsmanager:eu-west-2:038774803581:secret:prometheus-db-creds-*" #this was just *   before making it specifc to my secret on AWS
        ]
      }
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
resource "kubectl_manifest" "secret_store_app_space" {
  yaml_body = <<EOF
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets
  namespace: app-space
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
    data.aws_secretsmanager_secret.secrets,
    helm_release.external_secrets
  ]
}

resource "kubectl_manifest" "secret_store_data_space" {
  yaml_body = <<EOF
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets
  namespace: data-space
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
    data.aws_secretsmanager_secret.secrets,
    helm_release.external_secrets
  ]
}

resource "kubectl_manifest" "secret_store_monitoring" {
  yaml_body = <<EOF
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets
  namespace: monitoring
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
    data.aws_secretsmanager_secret.prometheus_secrets,
    helm_release.external_secrets
  ]
}


##Secret to fetch from AWS Secrets Manager and create a k8s secret so shipping pod can authenticate to mysql
resource "kubectl_manifest" "external_secret_mysql" {
  yaml_body = <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: mysql-secret
  namespace: app-space
spec:
  refreshInterval: 5m
  secretStoreRef:
    name: aws-secrets
    kind: SecretStore
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
    kubectl_manifest.secret_store_app_space,
    kubectl_manifest.deployments_namespace,
    data.aws_secretsmanager_secret.secrets
  ]
}

## RabbitMq secret which lives in data-space

resource "kubectl_manifest" "external_secret_rabbitmq" {
  yaml_body = <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: rabbitmq-secret
  namespace: data-space
spec:
  refreshInterval: 5m
  secretStoreRef:
    name: aws-secrets
    kind: SecretStore
  target:
    name: rabbitmq-secret
  data:
    - secretKey: RABBITMQ_DEFAULT_USER
      remoteRef:
        key: db-creds
        property: RABBITMQ_DEFAULT_USER
    - secretKey: RABBITMQ_DEFAULT_PASS
      remoteRef:
        key: db-creds
        property: RABBITMQ_DEFAULT_PASS
EOF
  depends_on = [kubectl_manifest.secret_store_data_space,
    kubectl_manifest.databases_namespace,
  data.aws_secretsmanager_secret.secrets]
}


resource "kubectl_manifest" "external_secret_payment" {
  yaml_body = <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: payment-secret
  namespace: app-space
spec:
  refreshInterval: 5m
  secretStoreRef:
    name: aws-secrets
    kind: SecretStore
  target:
    name: payment-rabbitmq-secret
  data:
    - secretKey: RABBITMQ_DEFAULT_USER
      remoteRef:
        key: db-creds
        property: RABBITMQ_DEFAULT_USER
    - secretKey: RABBITMQ_DEFAULT_PASS
      remoteRef:
        key: db-creds
        property: RABBITMQ_DEFAULT_PASS
EOF
  depends_on = [kubectl_manifest.secret_store_app_space,
    kubectl_manifest.deployments_namespace,
  data.aws_secretsmanager_secret.secrets]
}



resource "kubectl_manifest" "mysql_exporter_secret" {
  yaml_body = <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: mysql-metrics-credentials
  namespace: monitoring
spec:
  refreshInterval: 5m
  secretStoreRef:
    name: aws-secrets
    kind: SecretStore
  target:
    name: mysql-exporter-mycnf
  data:
    - secretKey: .my.cnf
      remoteRef:
        key: prometheus-db-creds
        property: mycnf_content
EOF

  depends_on = [
    kubectl_manifest.secret_store_monitoring,
    kubectl_manifest.monitoring_namespace,
    data.aws_secretsmanager_secret.prometheus_secrets
  ]
}


resource "kubectl_manifest" "redis_exporter_secret" {
  yaml_body = <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: redis-exporter-credentials
  namespace: monitoring
spec:
  refreshInterval: 5m
  secretStoreRef:
    name: aws-secrets
    kind: SecretStore
  target:
    name: redis-secret
  data:
    - secretKey: REDIS_PASSWORD
      remoteRef:
        key: prometheus-db-creds
        property: REDIS_PASSWORD
EOF

  depends_on = [
    kubectl_manifest.secret_store_monitoring,
    kubectl_manifest.monitoring_namespace,
    data.aws_secretsmanager_secret.prometheus_secrets
  ]
}


resource "kubectl_manifest" "gmail_password_alertmanager" {
  yaml_body = <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: alertmanager-config
  namespace: monitoring
spec:
  refreshInterval: 5m
  secretStoreRef:
    name: aws-secrets
    kind: SecretStore
  target:
    name: alertmanager-gmail-secret
  data:
    - secretKey: gmail_password
      remoteRef:
        key: prometheus-db-creds
        property: gmail_password
EOF

  depends_on = [
    kubectl_manifest.secret_store_monitoring,
    kubectl_manifest.monitoring_namespace,
    data.aws_secretsmanager_secret.prometheus_secrets
  ]
}