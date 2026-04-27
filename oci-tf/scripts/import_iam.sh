#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# import_iam.sh
#
# apply-iam 실행 전, OCI에 이미 존재하는 IAM 리소스를
# Terraform state에 import하여 409-AlreadyExists 에러를 방지합니다.
#
# 동작:
#   1. OCI CLI로 Dynamic Group OCID 조회
#   2. OCI CLI로 Policy OCID 조회
#   3. 각각 state에 없으면 terraform import 실행
# ──────────────────────────────────────────────────────────────
set -euo pipefail

TFVARS="${1:-terraform.tfvars}"

# tfvars에서 값 추출
TENANCY_ID=$(grep '^tenancy_ocid' "$TFVARS" | awk -F'"' '{print $2}')
PREFIX=$(grep '^prefix'      "$TFVARS" | awk -F'"' '{print $2}')

DG_NAME="${PREFIX}-oke-nodes-dg"
POLICY_NAME="${PREFIX}-oke-lb-controller-policy"

echo "[import-iam] tenancy: $TENANCY_ID"
echo "[import-iam] DG     : $DG_NAME"
echo "[import-iam] Policy : $POLICY_NAME"

# ── Dynamic Group import ──────────────────────────────────────
DG_OCID=$(oci iam dynamic-group list \
  --compartment-id "$TENANCY_ID" \
  --all \
  --query "data[?name=='$DG_NAME'].id | [0]" \
  --raw-output 2>/dev/null || true)

if [ -n "$DG_OCID" ] && [ "$DG_OCID" != "null" ]; then
  # state에 이미 있으면 import 불필요
  if terraform state show module.iam.oci_identity_dynamic_group.oke_nodes \
       >/dev/null 2>&1; then
    echo "[import-iam] DG: 이미 state에 존재 → skip"
  else
    echo "[import-iam] DG import: $DG_OCID"
    terraform import module.iam.oci_identity_dynamic_group.oke_nodes "$DG_OCID"
  fi
else
  echo "[import-iam] DG: OCI에 없음 → terraform이 신규 생성합니다"
fi

# ── Policy import ─────────────────────────────────────────────
POLICY_OCID=$(oci iam policy list \
  --compartment-id "$TENANCY_ID" \
  --all \
  --query "data[?name=='$POLICY_NAME'].id | [0]" \
  --raw-output 2>/dev/null || true)

if [ -n "$POLICY_OCID" ] && [ "$POLICY_OCID" != "null" ]; then
  if terraform state show module.iam.oci_identity_policy.oke_lb_controller \
       >/dev/null 2>&1; then
    echo "[import-iam] Policy: 이미 state에 존재 → skip"
  else
    echo "[import-iam] Policy import: $POLICY_OCID"
    terraform import module.iam.oci_identity_policy.oke_lb_controller "$POLICY_OCID"
  fi
else
  echo "[import-iam] Policy: OCI에 없음 → terraform이 신규 생성합니다"
fi

echo "[import-iam] 완료 ✅"
