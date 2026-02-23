
####RBAC 

#Cart Service Account
resource "kubectl_manifest" "cart_sa" {
  yaml_body = <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cart-sa
  namespace: app-space
EOF
}

#Catalogue Service Account
resource "kubectl_manifest" "catalogue_sa" {
  yaml_body = <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: catalogue-sa
  namespace: app-space
EOF
}

#Web Service Account
resource "kubectl_manifest" "web_sa" {
  yaml_body = <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: web-sa
  namespace: app-space
EOF
}



#Ratings Service Account
resource "kubectl_manifest" "ratings_sa" {
  yaml_body = <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ratings-sa
  namespace: app-space
EOF
}

#User Service Account
resource "kubectl_manifest" "user_sa" {
  yaml_body = <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: user-sa
  namespace: app-space
EOF
}



##Mongo Service Account

resource "kubectl_manifest" "mongo_sa" {
  yaml_body = <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: mongo-sa
  namespace: data-space
EOF
}

##Redis Service Account

resource "kubectl_manifest" "redis_sa" {
  yaml_body = <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: redis
  namespace: data-space
EOF
}

##Roles and RoleBindings

##Read only access to the secret
resource "kubectl_manifest" "shipping_rbac_role" {
  yaml_body = <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: shipping-secret-reader
  namespace: app-space
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: ["mysql-secret"]
    verbs: ["get", "list"]
EOF
}



resource "kubectl_manifest" "shipping_rbac_rolebinding" {
  yaml_body = <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: shipping-secret-reader-binding
  namespace: shipping
subjects:
  - kind: ServiceAccount
    name: shipping-sa
    namespace: app-space
roleRef:
  kind: Role
  name: shipping-secret-reader
  apiGroup: rbac.authorization.k8s.io
EOF

}


resource "kubectl_manifest" "cart_rbac_role" {
  yaml_body = <<EOF

kind: Role
metadata:
  name: cart-secret-reader
  namespace: data-space
rules:
- apiGroups: [""]
  resources: ["configmap"]
  resourceNames: ["redis-credentials"]
  verbs: ["get"]
EOF
}

resource "kubectl_manifest" "cart_rbac_rolebinding" {
  yaml_body = <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: shipping-secret-binding
  namespace: data-space
subjects:
- kind: ServiceAccount
  name: cart-sa
  namespace: data-space
roleRef:
  kind: Role
  name: shipping-secret-reader
  apiGroup: rbac.authorization.k8s.io

EOF
}

resource "kubectl_manifest" "catalogue_rbac_role" {
  yaml_body = <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: catalogue-secret-reader
  namespace: robotshop
rules:
- apiGroups: [""]
  resources: ["configmap"]
  resourceNames: ["catalogue-credentials"]
  verbs: ["get"]
EOF
}

resource "kubectl_manifest" "catalogue_rbac_rolebinding" {
  yaml_body = <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: catalogue-secret-binding
  namespace: data-space
subjects:
- kind: ServiceAccount
  name: catalogue-sa
  namespace: data-space
roleRef:
  kind: Role
  name: shipping-secret-reader
  apiGroup: rbac.authorization.k8s.io

EOF
}

resource "kubectl_manifest" "payment_rbac_role" {
  yaml_body = <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: catalogue-secret-reader
  namespace: app-space
rules:
- apiGroups: [""]
  resources: ["configmap"]
  resourceNames: ["payment-credentials"]
  verbs: ["get"]
EOF
}

resource "kubectl_manifest" "payment_rbac_rolebinding" {
  yaml_body = <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: catalogue-secret-binding
  namespace: data-space
subjects:
- kind: ServiceAccount
  name: catalogue-sa
  namespace: data-space
roleRef:
  kind: Role
  name: shipping-secret-reader
  apiGroup: rbac.authorization.k8s.io

EOF
}






##Protect Argocd Password using ESO

resource "kubernetes_manifest" "external_secret" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "argocd-admin-secret"
      namespace = "argo-cd"
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "secretstore"
        kind = "ClusterSecretStore"
      }
      target = {
        name = "argocd-secret"
      }
      data = [
        {
          secretKey = "admin.password"
          remoteRef = {
            key      = "argocd-admin"
            property = "password"
          }

        }
      ]
    }
  }
}



apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
  namespace: app-space   
spec:
  serviceName: mysql
  replicas: 1
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
        - name: mysql
          image: 038774803581.dkr.ecr.eu-west-2.amazonaws.com/mysql:v1
          ports:
            - containerPort: 3306
              name: mysql
          env:
            - name: MYSQL_DATABASE
              value: cities
            - name: MYSQL_ROOT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mysql-secret
                  key: root-password
            - name: MYSQL_USER
              value: shipping
            - name: MYSQL_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mysql-secret
                  key: user-password
          resources:
            requests:
              cpu: "100m"
              memory: "256Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
          volumeMounts:
            - name: mysql-data
              mountPath: /var/lib/mysql
              subPath: mysql
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - |
                  mysqladmin ping \
                    -h 127.0.0.1 \
                    -u root \
                    -p"$MYSQL_ROOT_PASSWORD" \
                    --silent
            initialDelaySeconds: 30
            periodSeconds: 10

  volumeClaimTemplates:
    - metadata:
        name: mysql-data
      spec:
        accessModes:
          - ReadWriteOnce
        storageClassName: mysql-gp3
        resources:
          requests:
            storage: 5Gi



#apiVersion: v1
#kind: Secret
#metadata:
 # name: mysql-secret
  #namespace: app-space    
#type: Opaque
#stringData:
 # root-password: rootpass
  #user-password: secret


---


###IRSA for shipping pod so it can access AWS Secrets Manager

#resource "aws_iam_role" "shipping_irsa" {
#name = "iam-secrets-access"

# assume_role_policy = jsonencode({
# Version = "2012-10-17"
#  Statement = [
#  {
#   Effect = "Allow"
# Principal = {
#   Federated = "${aws_iam_openid_connect_provider.eks.arn}"
#  }
#  Action = "sts:AssumeRoleWithWebIdentity"
# Condition = {
#  StringEquals = {
#    "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:app-space:shipping_sa",
#  "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
#  }
# }
#}
#]
# })
#}


#resource "aws_iam_policy" "shipping_secrets_policy" {
# name = "shipping-secrets-manager-access"

# policy = jsonencode({
# Version = "2012-10-17"
# Statement = [
#  {
# Effect = "Allow"
# Action = [
#  "secretsmanager:GetSecretValue",
# #  "secretsmanager:DescribeSecret"
#]
# Resource = "arn:aws:secretsmanager:eu-west-2:*:secret:robotshop/shipping/*"
# }
#]
#})
#}

#resource "aws_iam_role_policy_attachment" "shipping_policy_irsa" {
# role       = aws_iam_role.shipping_irsa.name
#policy_arn = aws_iam_policy.shipping_secrets_policy.arn
#}



kubectl get secret argocd-initial-admin-secret -n argo-cd -o jsonpath="{.data.password}" | base64 --decode; echo

kubectl get secret prometheus-grafana -n monitoring -o jsonpath="{.data.admin-password}" | base64 --decode; echo