variable "compartment_id" { type = string }
variable "prefix" { type = string }
variable "vcn_cidr" { type = string }
variable "lb_subnet_cidr" { type = string }
variable "worker_subnet_cidr" { type = string }
variable "api_subnet_cidr" { type = string }
variable "admin_cidr" { type = string }
variable "tags" { type = map(string) }

variable "argocd_repo_endpoints" {
  description = "ArgoCD가 outbound로 접근해야 하는 외부 Git repo 엔드포인트 (host CIDR + TCP 포트)"
  type = list(object({
    cidr = string
    port = number
  }))
  default = []
}
