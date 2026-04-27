# ──────────────────────────────────────────
# OCI Identity (필수 수정)
# ──────────────────────────────────────────
tenancy_ocid     = "ocid1.tenancy.oc1..aaaaaaaa2j7k7at33otjvl2f4tbbibikvo4f2imctcswp2dwyb5zmrxmw5yq"
user_ocid        = "ocid1.user.oc1..aaaaaaaatfun3ovfk5thriycsddg355q73ro3mwpe52ejymvlhbicpnm6daa"
fingerprint      = "35:3d:a9:b4:cd:26:f9:2a:a1:92:10:5d:ef:b1:f6:0b"
private_key_path = "~/.oci/oci_api_key.pem"
region           = "ap-chuncheon-1"
compartment_id   = "ocid1.tenancy.oc1..aaaaaaaa2j7k7at33otjvl2f4tbbibikvo4f2imctcswp2dwyb5zmrxmw5yq"

# ──────────────────────────────────────────
# 리소스 이름 prefix
# ──────────────────────────────────────────
prefix = "oke"

# ──────────────────────────────────────────
# 네트워크 CIDR
# ──────────────────────────────────────────
vcn_cidr           = "10.0.0.0/16"
lb_subnet_cidr     = "10.0.10.0/24"
worker_subnet_cidr = "10.0.20.0/24"
api_subnet_cidr    = "10.0.30.0/24"

# Bastion 또는 VPN IP (Private API endpoint 접근 허용)
admin_cidr = "10.0.0.0/8"

# ──────────────────────────────────────────
# OKE
# ──────────────────────────────────────────
kubernetes_version = "v1.34.2"
pods_cidr          = "10.244.0.0/16"
services_cidr      = "10.96.0.0/16"

# ──────────────────────────────────────────
# Node Pool (VM.Standard.A1.Flex - ARM)
# ──────────────────────────────────────────
node_shape          = "VM.Standard.A1.Flex"
node_ocpus          = 2
node_memory_gb      = 12
node_count          = 2
boot_volume_size_gb = 50

# ──────────────────────────────────────────
# Helm Chart 버전
# ──────────────────────────────────────────
oci_nic_chart_version       = "1.3.5"
nginx_ingress_chart_version = "4.10.0"
argocd_chart_version        = "6.7.3"

# ──────────────────────────────────────────
# Prometheus Stack
# ──────────────────────────────────────────
prometheus_stack_chart_version = "58.7.2"
grafana_admin_password         = "admin"

# ──────────────────────────────────────────
# 공통 태그
# ──────────────────────────────────────────
tags = {
  managed_by  = "terraform"
  environment = "dev"
  project     = "oke"
}
