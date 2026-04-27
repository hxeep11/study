output "argocd_namespace" {
  value = kubernetes_namespace_v1.argocd.metadata[0].name
}

output "nginx_ingress_namespace" {
  value = kubernetes_namespace_v1.nginx_ingress.metadata[0].name
}

output "monitoring_namespace" {
  value = kubernetes_namespace_v1.monitoring.metadata[0].name
}

# ArgoCD 초기 admin 패스워드 (base64 디코딩)
output "argocd_admin_password" {
  description = "ArgoCD 초기 admin 패스워드 (sensitive)"
  value = try(
    base64decode(data.kubernetes_secret_v1.argocd_initial_password.data["password"]),
    "not-yet-available"
  )
  sensitive = true
}
