
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