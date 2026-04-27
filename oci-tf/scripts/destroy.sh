#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# OKE 환경 안전 Destroy 스크립트
#
# 목적:
#   OCI LB Controller가 생성한 OCI Load Balancer는 Terraform
#   state 외부에 존재하므로, 먼저 Ingress/Service를 삭제하여
#   LB가 컨트롤러에 의해 정리된 후 Terraform destroy를 실행합니다.
#
# 실행: bash scripts/destroy.sh
# ──────────────────────────────────────────────────────────────

set -euo pipefail

TFVARS="terraform.tfvars"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

confirm() {
  read -r -p "$1 [y/N] " response
  [[ "$response" =~ ^[Yy]$ ]]
}

# ──────────────────────────────────────────────────────────────
# 사전 확인
# ──────────────────────────────────────────────────────────────
log_warn "⚠️  OKE 전체 환경이 삭제됩니다. 이 작업은 되돌릴 수 없습니다."
confirm "정말 destroy를 진행하시겠습니까?" || { log_info "취소되었습니다."; exit 0; }

# ──────────────────────────────────────────────────────────────
# Step-1: Kubernetes 리소스 정리 (OCI LB 삭제 트리거)
#
# ArgoCD Ingress 삭제 → OCI NIC가 OCI LB를 자동 삭제
# OCI NIC Helm 삭제 → IngressClass 삭제
# ──────────────────────────────────────────────────────────────
log_info "Step-1: Kubernetes Ingress/Service 정리 (OCI LB 회수 대기)"

if kubectl get ingress argocd-server -n argocd &>/dev/null 2>&1; then
  log_info "  ArgoCD Ingress 삭제 중..."
  kubectl delete ingress argocd-server -n argocd --ignore-not-found=true
  log_info "  OCI LB 삭제 대기 (60초)..."
  sleep 60
else
  log_warn "  ArgoCD Ingress 없음 (이미 삭제됨)"
fi

# gRPC Ingress도 삭제
kubectl delete ingress argocd-server-grpc -n argocd --ignore-not-found=true 2>/dev/null || true

# ──────────────────────────────────────────────────────────────
# Step-2: Helm Addons Terraform 삭제
#         (Helm release → K8s 리소스 정리)
# ──────────────────────────────────────────────────────────────
log_info "Step-2: Helm Addons (ArgoCD + OCI NIC) terraform destroy"

terraform destroy \
  -target=module.helm_addons \
  -var-file="${TFVARS}" \
  -auto-approve

log_info "  Helm 리소스 삭제 완료. OCI LB 최종 삭제 대기 (30초)..."
sleep 30

# ──────────────────────────────────────────────────────────────
# Step-3: OKE Node Pool Terraform 삭제
#         노드 drain → 노드 삭제 (시간 소요)
# ──────────────────────────────────────────────────────────────
log_info "Step-3: OKE Node Pool 삭제 (수 분 소요)"

terraform destroy \
  -target=module.oke.oci_containerengine_node_pool.main \
  -var-file="${TFVARS}" \
  -auto-approve

# ──────────────────────────────────────────────────────────────
# Step-4: OKE Cluster + IAM Terraform 삭제
# ──────────────────────────────────────────────────────────────
log_info "Step-4: OKE Cluster + IAM 삭제"

terraform destroy \
  -target=module.oke \
  -var-file="${TFVARS}" \
  -auto-approve

# ──────────────────────────────────────────────────────────────
# Step-5: Network (VCN, 서브넷, 게이트웨이) Terraform 삭제
#         OKE 클러스터가 완전히 삭제된 후에만 가능
# ──────────────────────────────────────────────────────────────
log_info "Step-5: Network 리소스 삭제"

terraform destroy \
  -target=module.network \
  -var-file="${TFVARS}" \
  -auto-approve

# ──────────────────────────────────────────────────────────────
# Step-6: 나머지 전체 삭제 (남은 state 정리)
# ──────────────────────────────────────────────────────────────
log_info "Step-6: 전체 state 최종 정리"

terraform destroy \
  -var-file="${TFVARS}" \
  -auto-approve

log_info "✅ 모든 리소스가 정상적으로 삭제되었습니다."
log_warn "   OCI 콘솔에서 LB/VCN 잔여 리소스 여부를 최종 확인하세요."
