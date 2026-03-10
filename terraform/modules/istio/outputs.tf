output "istiobase_helmchart" {
  value = helm_release.istio_base
}

output "istiod_helmchart" {
  value = helm_release.istiod
}
