output "cluster_id" {
  value = oci_containerengine_cluster.main.id
}

output "cluster_endpoint" {
  description = "OKE Public API Endpoint IP (kubeconfig host에 사용)"
  value       = oci_containerengine_cluster.main.endpoints[0].public_endpoint
}

data "oci_containerengine_cluster_kube_config" "kube_config" {
  # resource "oci_containerengine_cluster" "main" 을 참조합니다.
  cluster_id = oci_containerengine_cluster.main.id
}

output "cluster_ca_cert" {
  description = "Kubernetes Cluster CA Certificate"

  # yamldecode를 이용해 kubeconfig 내용에서 인증서 데이터만 추출합니다.
  value = yamldecode(data.oci_containerengine_cluster_kube_config.kube_config.content)["clusters"][0]["cluster"]["certificate-authority-data"]
}

output "node_pool_id" {
  value = oci_containerengine_node_pool.main.id
}

output "wait_signal" {
  description = "Helm 모듈 depends_on에서 노드 준비 완료 신호로 활용"
  value       = time_sleep.wait_for_nodes.id
}

output "kubeconfig_done" {
  description = "kubeconfig 등록 완료 신호 (helm-addons depends_on에 활용)"
  value       = null_resource.kubeconfig.id
}
