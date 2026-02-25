resource "kubectl_manifest" "deployments_namespace" {
  yaml_body = <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: app-space
EOF

  depends_on = [aws_eks_cluster.eks_cluster,
aws_eks_node_group.private_node_1,
aws_eks_node_group.private_node_2
]
}

resource "kubectl_manifest" "databases_namespace" {
  yaml_body = <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: data-space
EOF
  depends_on = [aws_eks_cluster.eks_cluster]
}


resource "kubectl_manifest" "external_secrets_namespace" {
  yaml_body = <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: external-secrets
EOF
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

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = "eso-sa"
  }


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
          Federated = "${aws_iam_openid_connect_provider.eks.arn}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:external-secrets:eso-sa",
            "${replace(aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
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
    kubectl_manifest.external_secrets_namespace

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
    kubectl_manifest.cluster_secret_store
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


resource "kubernetes_config_map" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }
## FOR Github OIDC
  data = {
    mapRoles = <<YAML
- rolearn: arn:aws:iam::038774803581:role/github.to.aws.oidc
  username: github-actions
  groups:
    - system:masters
YAML
##For IAM USER
    mapUsers = <<YAML
- userarn: arn:aws:iam::038774803581:user/terraform-test
  username: terraform-test
  groups:
    - system:masters
YAML
  }
  depends_on = [aws_eks_cluster.eks_cluster]

}