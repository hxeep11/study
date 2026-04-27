# ──────────────────────────────────────────────────────────────
# Network
# ──────────────────────────────────────────────────────────────
output "vcn_id" {
  description = "VCN OCID"
  value       = module.network.vcn_id
}

output "subnet_ids" {
  description = "서브넷 OCID 모음 (lb / workers / api)"
  value = {
    lb      = module.network.lb_subnet_id
    workers = module.network.worker_subnet_id
    api     = module.network.api_subnet_id
  }
}

# ──────────────────────────────────────────────────────────────
# OKE
# ──────────────────────────────────────────────────────────────
output "cluster_id" {
  description = "OKE Cluster OCID"
  value       = module.oke.cluster_id
}

output "cluster_endpoint" {
  description = "OKE Private API Endpoint IP"
  value       = module.oke.cluster_endpoint
}

output "kubeconfig_command" {
  description = "kubeconfig 수동 생성 명령어 (필요 시)"
  value = join(" ", [
    "oci ce cluster create-kubeconfig",
    "--cluster-id", module.oke.cluster_id,
    "--region", var.region,
    "--token-version 2.0.0",
    "--kube-endpoint PRIVATE_ENDPOINT",
    "--file ~/.kube/config --merge",
  ])
}

output "kubectl_context" {
  description = "OKE kubectl context 이름"
  value       = "context-${module.oke.cluster_id}"
}

# ──────────────────────────────────────────────────────────────
# NGINX Ingress LB (유일한 LB — ArgoCD + Grafana 라우팅)
# ──────────────────────────────────────────────────────────────
output "nginx_ingress_lb_command" {
  description = "NGINX Ingress LB IP 확인 명령어"
  value       = "kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
}

# ──────────────────────────────────────────────────────────────
# ArgoCD (NGINX Ingress / 경유)
# ──────────────────────────────────────────────────────────────
output "argocd_admin_username" {
  description = "ArgoCD 관리자 계정"
  value       = "admin"
}

output "argocd_admin_password" {
  description = "ArgoCD 초기 admin 패스워드 (sensitive)"
  value       = module.helm_addons.argocd_admin_password
  sensitive   = true
}

output "argocd_password_reveal_command" {
  description = "패스워드 확인 명령어 (terraform output 또는 kubectl)"
  value       = <<-EOT
    # 방법 1: Terraform output (권장)
    terraform output -raw argocd_admin_password

    # 방법 2: kubectl
    kubectl -n argocd get secret argocd-initial-admin-secret \
      -o jsonpath='{.data.password}' | base64 -d && echo
  EOT
}

# ──────────────────────────────────────────────────────────────
# Prometheus Stack (Grafana)
# ──────────────────────────────────────────────────────────────
output "grafana_admin_password" {
  description = "Grafana 초기 admin 패스워드 (sensitive)"
  value       = var.grafana_admin_password
  sensitive   = true
}

output "prometheus_port_forward_command" {
  description = "Prometheus UI 접근 (kubectl port-forward)"
  value       = "kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090"
}

output "region" {
  description = "OCI Region"
  value       = var.region
}
