output "dynamic_group_name" {
  description = "생성된 Dynamic Group 이름"
  value       = oci_identity_dynamic_group.oke_nodes.name
}

output "dynamic_group_id" {
  description = "생성된 Dynamic Group OCID"
  value       = oci_identity_dynamic_group.oke_nodes.id
}

output "policy_id" {
  description = "생성된 IAM Policy OCID"
  value       = oci_identity_policy.oke_lb_controller.id
}

# OKE 모듈 등 하위 모듈의 depends_on에서 IAM 완료 신호로 활용
output "iam_ready" {
  description = "IAM 리소스 생성 완료 신호"
  value       = oci_identity_policy.oke_lb_controller.id
}
