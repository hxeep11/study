# ──────────────────────────────────────────────────────────────
# OKE 클러스터 접속 정보 (Step-2 apply 이후 값이 확정됨)
#
# Kubernetes / Helm Provider가 이 값을 참조합니다.
# Private Endpoint 특성상 apply 실행 환경이 VCN 내부여야 합니다.
# ──────────────────────────────────────────────────────────────
locals {
  cluster_id       = module.oke.cluster_id
  cluster_endpoint = module.oke.cluster_endpoint
  cluster_ca_cert  = module.oke.cluster_ca_cert
}
