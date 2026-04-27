variable "compartment_id" { type = string }
variable "prefix" { type = string }
variable "lb_subnet_id" { type = string }
variable "region" { type = string }
variable "oci_nic_chart_version" { type = string }
variable "nginx_ingress_chart_version" {
  type    = string
  default = "4.10.0"
}
variable "argocd_chart_version" { type = string }
variable "tags" { type = map(string) }

# ── Prometheus Stack ──────────────────────────────────────────
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
