#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# OCI Orphan Private IP Cleanup
#
# 목적:
#   LB/VNIC 삭제 후 서브넷에 남은 "찌꺼기" private IP 정리.
#   각 private IP의 vnic-id로 VNIC 조회 → 404면 orphan 으로 판정 후 삭제.
#
# 사용법:
#   bash scripts/cleanup_private_ips.sh           # LB 서브넷만 (기본)
#   bash scripts/cleanup_private_ips.sh all       # LB + workers + api
#   DRY_RUN=1 bash scripts/cleanup_private_ips.sh # 삭제 없이 후보만 출력
# ──────────────────────────────────────────────────────────────

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

DRY_RUN="${DRY_RUN:-0}"
SCOPE="${1:-lb}"

command -v oci >/dev/null || { log_error "oci CLI 미설치"; exit 1; }
command -v jq  >/dev/null || { log_error "jq 미설치"; exit 1; }

# ──────────────────────────────────────────────────────────────
# 대상 서브넷 OCID 수집 (terraform output 기반)
# ──────────────────────────────────────────────────────────────
get_subnet_id() {
  local key="$1"
  terraform output -json subnet_ids 2>/dev/null | jq -r ".${key} // empty"
}

declare -a SUBNETS=()
case "$SCOPE" in
  lb)   SUBNETS+=("$(get_subnet_id lb)") ;;
  all)  SUBNETS+=("$(get_subnet_id lb)" "$(get_subnet_id workers)" "$(get_subnet_id api)") ;;
  *)    log_error "알 수 없는 scope: $SCOPE (lb|all)"; exit 1 ;;
esac

for s in "${SUBNETS[@]}"; do
  [[ -z "$s" ]] && { log_error "서브넷 OCID를 찾지 못했습니다. terraform output subnet_ids 확인"; exit 1; }
done

# ──────────────────────────────────────────────────────────────
# Orphan 판정 + 삭제
# ──────────────────────────────────────────────────────────────
total_found=0
total_deleted=0

for SUBNET_ID in "${SUBNETS[@]}"; do
  log_info "서브넷 스캔: $SUBNET_ID"

  PIPS_JSON=$(oci network private-ip list --subnet-id "$SUBNET_ID" --all 2>/dev/null || echo '{"data":[]}')
  COUNT=$(echo "$PIPS_JSON" | jq '.data | length')
  log_info "  Private IP 총 ${COUNT}개"

  while IFS=$'\t' read -r PIP_ID PIP_ADDR VNIC_ID IS_PRIMARY; do
    [[ -z "$PIP_ID" ]] && continue

    if [[ -z "$VNIC_ID" || "$VNIC_ID" == "null" ]]; then
      log_warn "  [orphan-no-vnic] $PIP_ADDR ($PIP_ID)"
      ORPHAN=1
    else
      if oci network vnic get --vnic-id "$VNIC_ID" >/dev/null 2>&1; then
        ORPHAN=0
      else
        log_warn "  [orphan-stale-vnic] $PIP_ADDR vnic=$VNIC_ID"
        ORPHAN=1
      fi
    fi

    if [[ "$ORPHAN" == "1" ]]; then
      total_found=$((total_found+1))
      if [[ "$IS_PRIMARY" == "true" ]]; then
        log_warn "    primary IP 는 삭제 불가 (VNIC 삭제로만 회수). 건너뜀."
        continue
      fi
      if [[ "$DRY_RUN" == "1" ]]; then
        log_info "    DRY_RUN: 삭제 대상 → $PIP_ADDR"
      else
        oci network private-ip delete --private-ip-id "$PIP_ID" --force >/dev/null \
          && { log_info "    삭제 완료: $PIP_ADDR"; total_deleted=$((total_deleted+1)); } \
          || log_error "    삭제 실패: $PIP_ADDR"
      fi
    fi
  done < <(echo "$PIPS_JSON" | jq -r '.data[] | [.id, ."ip-address", ."vnic-id", ."is-primary"] | @tsv')
done

log_info "완료: orphan ${total_found}개 발견 / 삭제 ${total_deleted}개 (DRY_RUN=${DRY_RUN})"
