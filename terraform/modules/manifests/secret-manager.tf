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

resource "kubectl_manifest" "external_secrets__namespace" {
  yaml_body = <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: external-secrets
EOF
}

##Creates the container to store secrets
resource "aws_secretsmanager_secret" "secrets" {
  name       = "db-creds"
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
  
  set  {
    name = "serviceAccount.create"
    value = "false"
  }

  set   {
    name = "serviceAccount.name"
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
   aws_iam_role_policy_attachment.iampolicyattach-eso
  ]
}

##Reference to AWS Secrets Manager and tells k8s where to fetch secrets
resource "kubernetes_manifest" "cluster_secret_store" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata = {
      name      = "secretstore"
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = "eu-west-2"
          auth = {
            jwt = {
              serviceAccountRef = {
                name = "eso-sa"
                namespace = "external-secrets"
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_service_account_v1.eso_serviceaact,
    aws_secretsmanager_secret_version.secrets,
    aws_secretsmanager_secret.secrets,
    helm_release.external_secrets
  ]
}


##What Secret to fetch from AWS Secrets Manager and create a k8s secret
resource "kubernetes_manifest" "external_secret" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "shipping-db-secret"
      namespace = "app-space"
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "secretstore"
        kind = "ClusterSecretStore"
      }
      target = {
        name = "kube-secret"
      }
      data = [
        {
          secretKey = "DB_USER"
          remoteRef = {
            key      = "db-creds"
            property = "DB_USER"
          }
        },
        {
          secretKey = "DB_PASSWORD"
          remoteRef = {
            key      = "db-creds"
            property = "DB_PASSWORD"
          }
        }
      ]
    }
  }

  depends_on = [
    kubernetes_manifest.cluster_secret_store
  ]
}



##IAM Role for payment pod

#resource "aws_iam_role" "secrets_csi_payment_role" {
  #name = "iamrole-payment-csidriver"

  #assume_role_policy = jsonencode({
    #Version = "2012-10-17"
   # Statement = [
     # {
       # Effect = "Allow"
       # Principal = {
      #    Federated = "${var.oidc_provider_arn}"
      #  }
      #  Action = "sts:AssumeRoleWithWebIdentity"
      #  Condition = {
      #    StringEquals = {
      #      "${replace(var.oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:app-space:payment-sa",
          #  "${replace(var.oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
         # }
       # }
     # }
    #]
 # })
#}



###IAM Role for mysql pod

#resource "aws_iam_role" "secrets_csi_mysql_role" {
 # name = "iamrole-mysql-csidriver"

 # assume_role_policy = jsonencode({
    ##Version = "2012-10-17"
   # Statement = [
    #  {
      #  Effect = "Allow"
      #  Principal = {
      #    Federated = "${var.oidc_provider_arn}"
       # }
       # Action = "sts:AssumeRoleWithWebIdentity"
       # Condition = {
        #  StringEquals = {
          #  "${replace(var.oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:app-space:mysql-sa",
          #  "${replace(var.oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
         # }
        #}
      #}
   # ]
  #})
#}



#resource "aws_iam_role_policy_attachment" "mysql_secrets_csi_driver" {
 # role       = aws_iam_role.secrets_csi_mysql_role.name
 # policy_arn = aws_iam_policy.secrets_csi_policy.arn
#}

#resource "aws_iam_role_policy_attachment" "payment_secrets_csi_driver" {
 # role       = aws_iam_role.secrets_csi_payment_role.name
  #policy_arn = aws_iam_policy.secrets_csi_policy.arn
#}



###For mysql 

#resource "kubernetes_service_account_v1" "mysql_serviceacct" {
 # metadata {
  ##  name      = "mysql-sa"
   # namespace = "app-space"
   # annotations = {
   # #  "eks.amazonaws.com/role-arn" = aws_iam_role.secrets_csi_mysql_role.arn
   #}
  #}
 # depends_on = [kubectl_manifest.secrets_manager_namespace,
   # aws_iam_role_policy_attachment.mysql_secrets_csi_driver
  #]
#}



##Payment

#resource "kubernetes_service_account_v1" "payment_serviceacct" {
 # metadata {
  #  name      = "payment-sa"
   # namespace = "app-space"
   # annotations = {
    #  "eks.amazonaws.com/role-arn" = aws_iam_role.secrets_csi_payment_role.arn
  # # }
 # }
  #depends_on = [kubectl_manifest.secrets_manager_namespace,
   # aws_iam_role_policy_attachment.payment_secrets_csi_driver
 # ]
#}



