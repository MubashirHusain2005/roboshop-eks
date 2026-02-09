terraform {
  required_version = "1.13.3"
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.10.0"
    }
  }
}

##MySql Service Account

resource "kubectl_manifest" "mysql_sa" {
  count = var.enable_rbac ? 1 : 0

  yaml_body = <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
    name: mysql-sa
    namespace: app-space
EOF
}

###RBAC Role so only the Mysql stateful set can read secrets

resource "kubectl_manifest" "msql_secret_role" {
 count = var.enable_rbac ? 1 : 0
  yaml_body = <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: mysql-secret-reader
  namespace: app-space
rules:
- apiGroups: [""]
  resources: ["secrets"]
  resourceNames: ["mysql-credentials"]
  verbs: ["get"]
EOF

  depends_on = [kubectl_manifest.mysql_secret,
    kubectl_manifest.mysql_statefulset
  ]
}

###RBAC RoleBinding
resource "kubectl_manifest" "msql_secret_binding" {
  count = var.enable_rbac ? 1 : 0

  yaml_body = <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: mysql-read-secret
  namespace: app-space
subjects:
- kind: ServiceAccount
  name: mysql-sa
roleRef:
  kind: Role
  name: mysql-secret-reader
  apiGroup: rbac.authorization.k8s.io
EOF
depends_on = [kubectl_manifest.mysql_secret,
    kubectl_manifest.mysql_statefulset]
}

####Junior Frontend Developers

resource "kubectl_manifest" "rbac_frontend_role" {
  count = var.enable_rbac ? 1 : 0

  yaml_body = <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: app-space
  name: junior-frontend
rules:
- apiGroups: [""]
  resources: ["pods", "deployments", "services"]
  verbs: ["get", "list"]

EOF
}

resource "kubectl_manifest" "rbac_frontend_binding" {
  count = var.enable_rbac ? 1 : 0

  yaml_body = <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: junior-frontend-binding
  namespace: app-space
subjects:
- kind: Group
  name: developer
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: junior-frontend
  apiGroup: rbac.authorization.k8s.io
EOF
}

###Platform Engineering Team

resource "kubectl_manifest" "rbac_platform_role" {
  count = var.enable_platform_rbac ? 1 : 0

    yaml_body = <<EOF

apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: node-viewer
rules:
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "list"]

EOF
}

resource "kubectl_manifest" "rbac_platform_binding" {
  count = var.enable_platform_rbac ? 1 : 0

    yaml_body = <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: node-viewer-binding
subjects:
- kind: Group
  name: platform-team
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: node-viewer
  apiGroup: rbac.authorization.k8s.io
EOF
}

##Backend Engineering Team

module "rbac" {
  source = "./modules/rbac"
  enable_rbac = var.enable_rbac
  enable_platform_rbac = var.enable_platform_rbac
}
