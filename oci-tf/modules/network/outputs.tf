output "vcn_id" { value = oci_core_vcn.main.id }
output "lb_subnet_id" { value = oci_core_subnet.lb.id }
output "worker_subnet_id" { value = oci_core_subnet.workers.id }
output "api_subnet_id" { value = oci_core_subnet.api.id }
output "nat_gateway_id" { value = oci_core_nat_gateway.main.id }
output "igw_id" { value = oci_core_internet_gateway.main.id }
