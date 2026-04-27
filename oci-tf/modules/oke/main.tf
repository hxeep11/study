# ──────────────────────────────────────────────────────────────
# Data Sources
# ──────────────────────────────────────────────────────────────

terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
    }
  }
}

# 첫 번째 AD 선택 (단일 AD 리전은 AD-1만 존재)
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_id
}

data "oci_identity_availability_domains" "ad" {
  compartment_id = var.compartment_id
}

# 👇 이 locals 블록 안에 ad_name이 반드시 있어야 합니다!
locals {
  # (하드코딩한 노드 이미지 OCID)
  node_image = "ocid1.image.oc1.ap-chuncheon-1.aaaaaaaa2l7pz4p2qmxnrpjuxyram6jypwmh2eeekskr7ou2crcbdrbyl2gq"

  # 👇 ad.availability_domains 를 ads.availability_domains 로 수정합니다!
  ad_name = data.oci_identity_availability_domains.ads.availability_domains[0].name
}

# ──────────────────────────────────────────────────────────────
# OKE Cluster (Enhanced: Workload Identity, VCN-native pod IP)
# ──────────────────────────────────────────────────────────────
resource "oci_containerengine_cluster" "main" {
  compartment_id     = var.compartment_id
  name               = "${var.prefix}-cluster"
  kubernetes_version = var.kubernetes_version
  vcn_id             = var.vcn_id
  type               = "ENHANCED_CLUSTER" # Instance Principal 사용 가능, Workload Identity도 지원

  cluster_pod_network_options {
    cni_type = "OCI_VCN_IP_NATIVE" # VCN-native pod 네트워킹 (더 나은 성능)
  }

  endpoint_config {
    is_public_ip_enabled = true # Public Endpoint
    subnet_id            = var.api_subnet_id
  }

  options {
    service_lb_subnet_ids = [var.lb_subnet_id]

    add_ons {
      # is_dashboard_enabled = false
      # is_tiller_enabled    = false
    }

    admission_controller_options {
      is_pod_security_policy_enabled = false
    }

    kubernetes_network_config {
      pods_cidr     = var.pods_cidr
      services_cidr = var.services_cidr
    }
  }

  image_policy_config {
    is_policy_enabled = false
  }

  freeform_tags = var.tags
}

# ──────────────────────────────────────────────────────────────
# Node Pool
# ──────────────────────────────────────────────────────────────
resource "oci_containerengine_node_pool" "main" {
  cluster_id         = oci_containerengine_cluster.main.id
  compartment_id     = var.compartment_id
  name               = "${var.prefix}-nodepool"
  kubernetes_version = var.kubernetes_version
  node_shape         = var.node_shape

  node_shape_config {
    ocpus         = var.node_ocpus
    memory_in_gbs = var.node_memory_gb
  }

  node_source_details {
    source_type             = "IMAGE"
    image_id                = local.node_image
    boot_volume_size_in_gbs = var.boot_volume_size_gb
  }

  node_config_details {
    size = var.node_count

    placement_configs {
      availability_domain = local.ad_name
      subnet_id           = var.worker_subnet_id
    }

    node_pool_pod_network_option_details {
      cni_type          = "OCI_VCN_IP_NATIVE"
      pod_subnet_ids    = [var.worker_subnet_id]
      max_pods_per_node = 31
    }

    freeform_tags = var.tags
  }

  # 이미지 ID와 k8s 버전은 외부 업그레이드 시 drift 방지를 위해 ignore
  lifecycle {
    ignore_changes = [
      node_source_details[0].image_id,
      kubernetes_version,
    ]
  }

  freeform_tags = var.tags
}

# ──────────────────────────────────────────────────────────────
# Node Pool 준비 완료 대기 (Helm 배포 전 노드 Ready 확인)
# ──────────────────────────────────────────────────────────────
resource "time_sleep" "wait_for_nodes" {
  create_duration = "120s" # 노드 부팅 및 kubelet 등록 대기

  triggers = {
    node_pool_id = oci_containerengine_node_pool.main.id
  }

  depends_on = [oci_containerengine_node_pool.main]
}

# ──────────────────────────────────────────────────────────────
# kubeconfig 자동 등록 + kubectl context 전환
#
# 동작:
#   1. oci ce cluster create-kubeconfig --merge
#      → 기존 ~/.kube/config에 OKE 클러스터 항목 추가 (덮어쓰지 않음)
#   2. kubectl config use-context <oke-context>
#      → 현재 context를 OKE로 전환
#
# [주의] Private Endpoint이므로 이 명령은 Bastion / VPN 환경에서만 동작
# ──────────────────────────────────────────────────────────────
resource "null_resource" "kubeconfig" {
  # OKE 클러스터 ID가 바뀔 때만 재실행
  triggers = {
    cluster_id = oci_containerengine_cluster.main.id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      CLUSTER_ID="${oci_containerengine_cluster.main.id}"
      REGION="${var.region}"
      KUBECONFIG_PATH="$${KUBECONFIG:-$HOME/.kube/config}"

      echo "[kubeconfig] OKE 클러스터 kubeconfig 병합 중..."
      # mktemp로 경로만 확보 후 즉시 삭제 → OCI CLI가 신규 파일로 생성하게 함
      TMPKUBE=$(mktemp /tmp/oke-kubeconfig-XXXXXX)
      rm -f "$TMPKUBE"

      oci ce cluster create-kubeconfig \
        --cluster-id  "$CLUSTER_ID" \
        --region      "$REGION" \
        --token-version 2.0.0 \
        --kube-endpoint PUBLIC_ENDPOINT \
        --file        "$TMPKUBE"

      # OCI CLI가 실제로 생성한 context 이름을 동적으로 읽음 (버전별 이름 형식 차이 대응)
      CONTEXT_NAME=$(KUBECONFIG="$TMPKUBE" kubectl config current-context)
      echo "[kubeconfig] 감지된 context 이름: $${CONTEXT_NAME}"

      # 기존 kubeconfig와 병합 후 원본 위치에 저장
      if [ -f "$KUBECONFIG_PATH" ]; then
        KUBECONFIG="$KUBECONFIG_PATH:$TMPKUBE" kubectl config view --flatten > "$${TMPKUBE}.merged"
        mv "$${TMPKUBE}.merged" "$KUBECONFIG_PATH"
      else
        mkdir -p "$(dirname "$KUBECONFIG_PATH")"
        mv "$TMPKUBE" "$KUBECONFIG_PATH"
      fi
      chmod 600 "$KUBECONFIG_PATH"
      rm -f "$TMPKUBE"

      # OCI CLI가 생성한 context 이름(OCID 포함 긴 문자열)을 "oke"로 rename
      echo "[kubeconfig] context rename: $${CONTEXT_NAME} → oke"
      kubectl config rename-context "$${CONTEXT_NAME}" "oke" 2>/dev/null || true
      kubectl config use-context "oke"

      echo "[kubeconfig] 완료 ✅  (current context: oke)"
      kubectl config current-context
    EOT
  }

  # destroy 시 context를 이전으로 복원 (선택)
  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      echo "[kubeconfig] context 'oke' 제거 중..."
      kubectl config delete-context "oke" 2>/dev/null || true
      kubectl config delete-cluster "oke"  2>/dev/null || true
      kubectl config unset "users.oke"     2>/dev/null || true

      echo "[kubeconfig] context 제거 완료"
    EOT
  }

  depends_on = [time_sleep.wait_for_nodes]
}
