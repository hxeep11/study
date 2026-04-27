output "lb_id" {
  description = "OCI Load Balancer OCID"
  value       = try(oci_load_balancer_load_balancer.argocd.id, null)
}

output "lb_ip" {
  description = "OCI Load Balancer Public IP"
  value       = try(oci_load_balancer_load_balancer.argocd.ip_address_details[0].ip_address, null)
}

output "lb_hostname" {
  description = "OCI LB DNS hostname (없을 경우 IP 반환)"
  value       = try(oci_load_balancer_load_balancer.argocd.ip_address_details[0].ip_address, "pending")
}
