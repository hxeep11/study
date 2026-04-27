# ──────────────────────────────────────────────────────────────
# OCI Load Balancer (인라인 리소스)
#
# terraform-oci-tdf-lb 업스트림 모듈 대신 인라인 리소스 사용
# 이유:
#   1. flexible shape 사용 시 shape_details 필수 → 업스트림 모듈 미지원
#   2. backends에 count 대신 for_each 사용 → (known after apply) 문제 해결
# ──────────────────────────────────────────────────────────────

# ── Load Balancer ─────────────────────────────────────────────
resource "oci_load_balancer_load_balancer" "argocd" {
  compartment_id = var.compartment_id
  display_name   = "${var.prefix}-argocd-lb"
  shape          = "flexible"

  shape_details {
    minimum_bandwidth_in_mbps = var.lb_min_bandwidth
    maximum_bandwidth_in_mbps = var.lb_max_bandwidth
  }

  subnet_ids    = [var.lb_subnet_id]
  is_private    = false
  freeform_tags = var.tags
}

# ── Health Check ──────────────────────────────────────────────
# OCI LB health check는 backend_set 내 health_checker 블록으로 정의
# (별도 리소스 불필요)

# ── Backend Set ───────────────────────────────────────────────
resource "oci_load_balancer_backend_set" "argocd" {
  load_balancer_id = oci_load_balancer_load_balancer.argocd.id
  name             = "argocd-bs"
  policy           = "ROUND_ROBIN"

  health_checker {
    protocol            = "HTTP"
    port                = var.argocd_nodeport
    url_path            = "/healthz"
    return_code         = 200
    timeout_in_millis   = 3000
    interval_ms         = 10000
    retries             = 3
    response_body_regex = ""
  }
}

# ── Backends (for_each → count unknown 문제 없음) ─────────────
resource "oci_load_balancer_backend" "argocd" {
  for_each = toset(var.worker_private_ips)

  load_balancer_id = oci_load_balancer_load_balancer.argocd.id
  backendset_name  = oci_load_balancer_backend_set.argocd.name
  ip_address       = each.value
  port             = var.argocd_nodeport
  backup           = false
  drain            = false
  offline          = false
  weight           = 1
}

# ── Listener ─────────────────────────────────────────────────
resource "oci_load_balancer_listener" "argocd_http" {
  load_balancer_id         = oci_load_balancer_load_balancer.argocd.id
  name                     = "argocd-http"
  default_backend_set_name = oci_load_balancer_backend_set.argocd.name
  port                     = 80
  protocol                 = "HTTP"

  connection_configuration {
    idle_timeout_in_seconds = 300
  }
}
