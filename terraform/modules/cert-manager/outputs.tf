output "letsencrypt_staging" {
  value = kubectl_manifest.istio_clusterissuer_staging.name
}

output "letsencrypt_prod" {
  value = kubectl_manifest.istio_clusterissuer_prod.name
}