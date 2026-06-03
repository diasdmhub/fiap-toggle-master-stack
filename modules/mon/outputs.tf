output "prometheus_release_name" {
  description = "Nome do Helm release do Prometheus Stack"
  value       = helm_release.prometheus_stack.name
}

output "prometheus_release_status" {
  description = "Status do Helm release do Prometheus Stack"
  value       = helm_release.prometheus_stack.status
}

output "loki_release_name" {
  description = "Nome do Helm release do Loki"
  value       = helm_release.loki.name
}

output "loki_release_status" {
  description = "Status do Helm release do Loki"
  value       = helm_release.loki.status
}

output "otel_release_name" {
  description = "Nome do Helm release do OpenTelemetry Collector"
  value       = helm_release.otel_collector.name
}

output "otel_release_status" {
  description = "Status do Helm release do OpenTelemetry Collector"
  value       = helm_release.otel_collector.status
}

output "otel_otlp_grpc_endpoint" {
  description = "Endpoint OTLP gRPC do Collector (para configurar nos microserviços)"
  value       = "otel-collector.monitoring.svc.cluster.local:4317"
}

output "otel_otlp_http_endpoint" {
  description = "Endpoint OTLP HTTP do Collector (para configurar nos microserviços)"
  value       = "http://otel-collector.monitoring.svc.cluster.local:4318"
}
