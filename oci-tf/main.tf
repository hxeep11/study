# ──────────────────────────────────────────────────────────────
# 배포 순서 (Dependency Chain)
#
#  [1] module.network
#       ↓
#  [2] module.oke
#       ├─ null_resource.kubeconfig  ← kubeconfig 등록 + context 전환
#       └─ time_sleep.wait_for_nodes
#       ↓
#  [3] module.helm_addons
#       ├─ NGINX Ingress Controller (LoadBalancer — 유일한 LB)
#       ├─ ArgoCD (ClusterIP → NGINX Ingress / 경유)
#       └─ kube-prometheus-stack (Grafana: NGINX Ingress /grafana 경유)
#
# 적용 명령:
#   make apply-infra   → Step-1~2 (network + oke + kubeconfig)
#   make apply         → Step-3   (helm addons)
# ──────────────────────────────────────────────────────────────

# ── 1. Network ───────────────────────────────────────────────
module "network" {
  source = "./modules/network"

  compartment_id        = var.compartment_id
  prefix                = var.prefix
  vcn_cidr              = var.vcn_cidr
  lb_subnet_cidr        = var.lb_subnet_cidr
  worker_subnet_cidr    = var.worker_subnet_cidr
  api_subnet_cidr       = var.api_subnet_cidr
  admin_cidr            = var.admin_cidr
  argocd_repo_endpoints = var.argocd_repo_endpoints
  tags                  = var.tags
}

# ── 1-1. IAM (Dynamic Group + Policy) ───────────────────────
# apply-iam 단계에서 먼저 배포 → 재배포 시 독립 재시도 가능
module "iam" {
  source = "./modules/iam"

  providers = {
    oci.home = oci.home
  }

  compartment_id = var.compartment_id
  tenancy_id     = var.tenancy_ocid
  prefix         = var.prefix
  tags           = var.tags
}

# ── 2. OKE Cluster + Node Pool + kubeconfig ──────────────────
module "oke" {
  source = "./modules/oke"

  providers = {
    oci = oci
  }

  compartment_id     = var.compartment_id
  tenancy_id         = var.tenancy_ocid
  prefix             = var.prefix
  region             = var.region
  kubernetes_version = var.kubernetes_version
  pods_cidr          = var.pods_cidr
  services_cidr      = var.services_cidr

  vcn_id           = module.network.vcn_id
  lb_subnet_id     = module.network.lb_subnet_id
  worker_subnet_id = module.network.worker_subnet_id
  api_subnet_id    = module.network.api_subnet_id

  node_shape          = var.node_shape
  node_ocpus          = var.node_ocpus
  node_memory_gb      = var.node_memory_gb
  node_count          = var.node_count
  boot_volume_size_gb = var.boot_volume_size_gb

  tags = var.tags

  depends_on = [module.network]
}

# ── 3. Helm Addons (NGINX IC + ArgoCD + Prometheus Stack) ────
# NGINX Ingress LB 하나로 ArgoCD + Grafana 모두 라우팅
module "helm_addons" {
  source = "./modules/helm-addons"

  compartment_id              = var.compartment_id
  prefix                      = var.prefix
  lb_subnet_id                = module.network.lb_subnet_id
  region                      = var.region
  oci_nic_chart_version       = var.oci_nic_chart_version
  nginx_ingress_chart_version = var.nginx_ingress_chart_version
  argocd_chart_version        = var.argocd_chart_version

  # Prometheus Stack
  prometheus_stack_chart_version = var.prometheus_stack_chart_version
  grafana_admin_password         = var.grafana_admin_password

  tags = var.tags

  depends_on = [module.oke]
}
