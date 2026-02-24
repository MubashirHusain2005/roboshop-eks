output "monitoring_namespace" {
  description = "Namespace to deploy observability charts"
  value       = var.monitoring_namespace
}

output "prometheus_helmchart" {
  value = helm_release.prometheus.name
}

