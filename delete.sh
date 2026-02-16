#!/bin/bash
set -e

# -----------------------------
# Cleanup Helm Releases + CRDs
# -----------------------------

echo "Starting cleanup of Helm charts and CRDs..."

# Helper function to uninstall a Helm release and its CRDs
uninstall_helm_release() {
  local release_name=$1
  local namespace=$2
  local keep_crds=$3

  if helm status "$release_name" -n "$namespace" >/dev/null 2>&1; then
    echo "Uninstalling Helm release: $release_name in namespace $namespace"
    helm uninstall "$release_name" -n "$namespace"

    if [ "$keep_crds" != "true" ]; then
      echo "Deleting CRDs for $release_name..."
      crds=$(kubectl get crds -o json | jq -r ".items[] | select(.metadata.labels.\"app.kubernetes.io/instance\"==\"$release_name\") | .metadata.name")
      for crd in $crds; do
        echo "Deleting CRD: $crd"
        kubectl delete crd "$crd" || true
      done
    fi
  else
    echo "Helm release $release_name not found in namespace $namespace. Skipping..."
  fi
}

# -----------------------------
# Delete Helm Releases
# -----------------------------

# ArgoCD
uninstall_helm_release "argocd" "argo-cd"

# ExternalDNS
uninstall_helm_release "external-dns" "kube-system"

# Cert-Manager
uninstall_helm_release "cert-manager" "cert-manager"

# NGINX Ingress Controller
uninstall_helm_release "ingress-nginx" "ingress-nginx"

# -----------------------------
# Optional: Delete Namespaces
# -----------------------------
namespaces=("argo-cd" "cert-manager" "ingress-nginx")

for ns in "${namespaces[@]}"; do
  if kubectl get ns "$ns" >/dev/null 2>&1; then
    echo "Deleting namespace $ns"
    kubectl delete ns "$ns"
  fi
done

# -----------------------------
# Optional: Delete leftover secrets, CRDs, and resources manually
# -----------------------------
echo "Deleting leftover ExternalSecrets..."
kubectl delete externalsecret --all -n argo-cd || true
kubectl delete clustersecretstore secretstore || true

echo "Deleting leftover ClusterRoles and ClusterRoleBindings..."
kubectl delete clusterrole argocd-application-controller || true
kubectl delete clusterrolebinding argocd-application-controller || true

echo "Cleanup complete."
