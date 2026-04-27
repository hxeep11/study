# ──────────────────────────────────────────────────────────────
# IAM - Dynamic Group + Policy (OKE worker node Instance Principal)
#
# OKE 워커 노드가 OCI Native Ingress Controller(NIC)를 통해
# Load Balancer를 제어할 수 있도록 필요한 IAM 리소스를 생성합니다.
#
# [주의] OCI IAM 리소스는 반드시 Home Region provider로 생성해야 합니다.
# ──────────────────────────────────────────────────────────────

terraform {
  required_providers {
    oci = {
      source                = "oracle/oci"
      configuration_aliases = [oci.home]
    }
  }
}

# ── 1. Dynamic Group ──────────────────────────────────────────
# compartment 내 모든 compute instance(=워커 노드)를 포함
resource "oci_identity_dynamic_group" "oke_nodes" {
  provider       = oci.home
  compartment_id = var.tenancy_id
  name           = "${var.prefix}-oke-nodes-dg"
  description    = "OKE worker nodes for instance principal auth"
  matching_rule  = "ALL {instance.compartment.id = '${var.compartment_id}'}"
  freeform_tags  = var.tags

  lifecycle {
    # 이미 존재하는 경우 drift 무시 (재배포 시 409 방지)
    ignore_changes = [matching_rule, description, freeform_tags]
  }
}

# ── 2. IAM 전파 대기 ──────────────────────────────────────────
# Dynamic Group이 생성된 직후 Policy에서 바로 참조하면
# "DG not found" 에러가 발생할 수 있어 120s 대기합니다.
resource "null_resource" "wait_for_dynamic_group" {
  triggers = {
    dg_id = oci_identity_dynamic_group.oke_nodes.id
  }

  provisioner "local-exec" {
    command = "echo '[IAM] DG 전파 대기 120s...' && sleep 120"
  }

  depends_on = [oci_identity_dynamic_group.oke_nodes]
}

resource "time_sleep" "wait_for_dynamic_group" {
  depends_on      = [null_resource.wait_for_dynamic_group]
  create_duration = "1s"
}

# ── 3. IAM Policy ─────────────────────────────────────────────
# Dynamic Group을 참조하는 Policy는 반드시 tenancy root에 생성
resource "oci_identity_policy" "oke_lb_controller" {
  provider       = oci.home
  compartment_id = var.tenancy_id
  name           = "${var.prefix}-oke-lb-controller-policy"
  description    = "Allow OKE nodes to manage Load Balancers via OCI Native Ingress Controller"

  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.oke_nodes.name} to manage load-balancers in tenancy",
    "Allow dynamic-group ${oci_identity_dynamic_group.oke_nodes.name} to use virtual-network-family in tenancy",
    "Allow dynamic-group ${oci_identity_dynamic_group.oke_nodes.name} to read cluster-family in tenancy",
    "Allow dynamic-group ${oci_identity_dynamic_group.oke_nodes.name} to manage leaf-certificate-family in tenancy",
  ]
  freeform_tags = var.tags

  depends_on = [time_sleep.wait_for_dynamic_group]

  lifecycle {
    # 이미 존재하는 경우 statements drift 무시 (재배포 시 409 방지)
    ignore_changes = [statements, description, freeform_tags]
  }
}
