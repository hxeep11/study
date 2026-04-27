variable "compartment_id" { type = string }
variable "prefix" { type = string }
variable "lb_subnet_id" { type = string }
variable "worker_private_ips" {
  type        = list(string)
  description = "OKE 워커 노드 Private IP 목록"
}
variable "argocd_nodeport" {
  type        = number
  description = "ArgoCD HTTP NodePort (고정값 32080)"
  default     = 32080
}
variable "lb_min_bandwidth" {
  type    = number
  default = 10
}
variable "lb_max_bandwidth" {
  type    = number
  default = 10
}
variable "tags" { type = map(string) }
