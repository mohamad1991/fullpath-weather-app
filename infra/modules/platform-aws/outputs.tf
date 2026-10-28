output "db_connection_secret_name" {
  value = aws_secretsmanager_secret.db_connection.name
}

output "app_namespace" {
  value = kubernetes_namespace_v1.app.metadata[0].name
}

output "grafana_admin_password" {
  value     = module.observability.grafana_admin_password
  sensitive = true
}
