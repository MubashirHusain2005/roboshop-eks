# SECRETS / CONFIGMAPS   

#resource "kubectl_manifest" "mysql_secret" {
 # yaml_body = <<EOF
#apiVersion: v1
#kind: Secret
#metadata:
 # name: mysql-secret
 # namespace: app-space    
#type: Opaque
#stringData:
 # root-password: rootpass
 # user-password: secret
#EOF

 #depends_on = [kubectl_manifest.db_namespace]
#}

resource "kubectl_manifest" "redis_configmap" {
  yaml_body = <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: redis-config
  namespace: data-space
data:
  redis.conf: |
    appendonly yes
    appendfsync everysec
EOF

  depends_on = [kubectl_manifest.db_namespace]
}

###Use AWS Secrets Manager for Shipping Pod and Mysql Pod to safely retrieve credentials
resource "helm_release" "secrets_csi_driver" {
  name = "secrets-store-csi-driver"

  repository = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
  chart      = "secrets-store-csi-driver"
  namespace  = "kube-system"
  version    = "1.4.3"

  set  {
    name  = "syncSecret.enabled"
    value = true
  }

}

resource "helm_release" "secrets_csi_driver_aws_provider" {
  name = "secrets-store-csi-driver-provider-aws"

  repository = "https://aws.github.io/secrets-store-csi-driver-provider-aws"
  chart      = "secrets-store-csi-driver-provider-aws"
  namespace  = "kube-system"
  version    = "0.3.8"

  depends_on = [helm_release.secrets_csi_driver]
}


resource "kubectl_manifest" "secrets_manager_namespace" {
  yaml_body = <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: secrets-manager
EOF
}

##IAM Role for payment pod

resource "aws_iam_role" "secrets_csi_payment_role" {
  name = "iamrole-payment-csidriver"

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
            "${replace(var.oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:app-space:payment-sa",
            "${replace(var.oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

##IAM Role for shipping pod
resource "aws_iam_role" "secrets_csi_shipping_role" {
  name = "iamrole-shipping-csidriver"

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
            "${replace(var.oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:app-space:shipping-sa",
            "${replace(var.oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

###IAM Role for mysql pod

resource "aws_iam_role" "secrets_csi_mysql_role" {
  name = "iamrole-mysql-csidriver"

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
            "${replace(var.oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:app-space:mysql-sa",
            "${replace(var.oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}


resource "aws_iam_policy" "secrets_csi_policy" {
  name = "iampolicy-secretscsi"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
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
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "shipping_secrets_csi_driver" {
  role       = aws_iam_role.secrets_csi_shipping_role.name
  policy_arn = aws_iam_policy.secrets_csi_policy.arn
}


resource "aws_iam_role_policy_attachment" "mysql_secrets_csi_driver" {
  role       = aws_iam_role.secrets_csi_mysql_role.name
  policy_arn = aws_iam_policy.secrets_csi_policy.arn
}

resource "aws_iam_role_policy_attachment" "payment_secrets_csi_driver" {
  role       = aws_iam_role.secrets_csi_payment_role.name
  policy_arn = aws_iam_policy.secrets_csi_policy.arn
}



###For shipping
resource "kubernetes_service_account_v1" "shipping_serviceacct" {
  metadata {
    name      = "shipping-sa"
    namespace = "app-space"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.secrets_csi_shipping_role.arn
    }
  }
  depends_on = [kubectl_manifest.secrets_manager_namespace,
    aws_iam_role_policy_attachment.shipping_secrets_csi_driver
  ]
}


###For mysql 

resource "kubernetes_service_account_v1" "mysql_serviceacct" {
  metadata {
    name      = "mysql-sa"
    namespace = "app-space"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.secrets_csi_mysql_role.arn
    }
  }
  depends_on = [kubectl_manifest.secrets_manager_namespace,
    aws_iam_role_policy_attachment.mysql_secrets_csi_driver
  ]
}


resource "aws_secretsmanager_secret" "secrets" {
  name       = "db-creds"
  kms_key_id = var.kms_key_id

}


resource "aws_secretsmanager_secret_version" "secrets" {
  secret_id     = aws_secretsmanager_secret.secrets.id
  secret_string = jsonencode(var.secrets)
}



##Payment

resource "kubernetes_service_account_v1" "payment_serviceacct" {
  metadata {
    name      = "payment-sa"
    namespace = "app-space"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.secrets_csi_payment_role.arn
    }
  }
  depends_on = [kubectl_manifest.secrets_manager_namespace,
    aws_iam_role_policy_attachment.payment_secrets_csi_driver
  ]
}



resource "kubectl_manifest" "secret_provider_class" {
  yaml_body = <<EOF

apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: db-secrets
  namespace: app-space
spec:
  provider: aws
  parameters:
    objects: |
      - objectName: "db-creds"
        objectType: "secretsmanager"
  secretObjects:
    - secretName: db-creds
      type: Opaque
      data:
        - objectName: root-password
          key: root-password
        - objectName: user-password
          key: user-password
        - objectName: DB_USER
          key: DB_USER
        - objectName: DB_PASSWORD
          key: DB_PASSWORD
        - objectName: RABBITMQ_PASSWORD
          key: RABBITMQ_PASSWORD
        - objectName: RABBITMQ_USER
          key: RABBITMQ_USER

EOF

}


