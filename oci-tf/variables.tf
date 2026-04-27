# ──────────────────────────────────────────
# OCI Identity
# ──────────────────────────────────────────
variable "tenancy_ocid" {
  type        = string
  description = "OCI Tenancy OCID"
}

variable "user_ocid" {
  type        = string
  description = "ocid1.user.oc1..aaaaaaaatfun3ovfk5thriycsddg355q73ro3mwpe52ejymvlhbicpnm6daa"
}

variable "fingerprint" {
  type        = string
  description = "35:3d:a9:b4:cd:26:f9:2a:a1:92:10:5d:ef:b1:f6:0b"
}

variable "private_key_path" {
  type        = string
  description = "=/root/.oci/oci_api_key.pem"
}

variable "region" {
  type        = string
  description = "OCI Region (e.g. ap-seoul-1)"
  default     = "	ap-seoul-1"
}

variable "compartment_id" {
  type        = string
  description = "ocid1.tenancy.oc1..aaaaaaaa2j7k7at33otjvl2f4tbbibikvo4f2imctcswp2dwyb5zmrxmw5yq"
}

# ──────────────────────────────────────────
# Common
# ──────────────────────────────────────────
variable "prefix" {
  type        = string
  description = "모든 리소스 이름 prefix"
  default     = "oke"
}

variable "tags" {
  type        = map(string)
  description = "공통 freeform tags"
  default = {
    managed_by  = "terraform"
    environment = "dev"
  }
}

# ──────────────────────────────────────────
# Network
# ──────────────────────────────────────────
variable "vcn_cidr" {
  type    = string
  default = "10.0.1.0/16"
}

variable "lb_subnet_cidr" {
  type        = string
  description = "Public LB 서브넷 CIDR"
  default     = "10.0.10.0/24"
}

variable "worker_subnet_cidr" {
  type        = string
  description = "Private 워커노드 서브넷 CIDR"
  default     = "10.0.20.0/24"
}

variable "api_subnet_cidr" {
  type        = string
  description = "Private OKE API Endpoint 서브넷 CIDR"
  default     = "10.0.30.0/24"
}

variable "admin_cidr" {
  type        = string
  description = "kubectl 접근 허용 CIDR (Bastion/VPN IP)"
  default     = "10.0.0.0/8"
}

variable "argocd_repo_endpoints" {
  description = "ArgoCD repo egress 허용 대상 (예: GitLab self-hosted host:port)"
  type = list(object({
    cidr = string
    port = number
  }))
  default = [
    { cidr = "158.101.80.134/32", port = 8080 }, # gitlab-repo-secret.yaml의 GitLab 호스트
  ]
}

# ──────────────────────────────────────────
# OKE Cluster
# ──────────────────────────────────────────
variable "kubernetes_version" {
  type    = string
  default = "v1.34.2"
}

variable "pods_cidr" {
  type    = string
  default = "10.244.0.0/16"
}

variable "services_cidr" {
  type    = string
  default = "10.96.0.0/16"
}

# ──────────────────────────────────────────
# Node Pool
# ──────────────────────────────────────────
variable "node_shape" {
  type    = string
  default = "VM.Standard.A1.Flex"
}

variable "node_ocpus" {
  type    = number
  default = 2
}

variable "node_memory_gb" {
  type    = number
  default = 12
}

variable "node_count" {
  type    = number
  default = 2
}

variable "boot_volume_size_gb" {
  type    = number
  default = 100
}

# ──────────────────────────────────────────
# Helm - OCI Native Ingress Controller
# ──────────────────────────────────────────
variable "oci_nic_chart_version" {
  type    = string
  default = "1.3.5"
}

variable "nginx_ingress_chart_version" {
  type    = string
  default = "4.10.0"
}

# ──────────────────────────────────────────
# Helm - ArgoCD
# ──────────────────────────────────────────
variable "argocd_chart_version" {
  type    = string
  default = "6.7.3"
}

# ──────────────────────────────────────────
# Helm - kube-prometheus-stack
# ──────────────────────────────────────────
variable "prometheus_stack_chart_version" {
  type    = string
  default = "58.7.2"
}

variable "grafana_admin_password" {
  type        = string
  default     = "admin"
  description = "Grafana 초기 admin 패스워드"
  sensitive   = true
}
