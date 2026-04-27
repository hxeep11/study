│ Error: Post "https://10.0.30.148:6443/api/v1/namespaces": dial tcp 10.0.30.148:6443: i/o timeout
│ 
│   with module.helm_addons.kubernetes_namespace_v1.argocd,
│   on modules/helm-addons/main.tf line 4, in resource "kubernetes_namespace_v1" "argocd":
│    4: resource "kubernetes_namespace_v1" "argocd" {
│ 
╵
╷
│ Error: Post "https://10.0.30.148:6443/api/v1/namespaces": dial tcp 10.0.30.148:6443: i/o timeout
│ 
│   with module.helm_addons.kubernetes_namespace_v1.nginx_ingress,
│   on modules/helm-addons/main.tf line 18, in resource "kubernetes_namespace_v1" "nginx_ingress":
│   18: resource "kubernetes_namespace_v1" "nginx_ingress" {
│ 
╵
make: *** [Makefile:69: apply] Error 1 에러
내부 module에서 10.대역의 ip로 oke 클러스터 kubeconfig를 구성하여 맞지 않음
Terraform이 Kubernetes namespace를 만들려고 10.0.30.148:6443에 POST를 보냈는데, 그 API 서버까지 TCP 연결 자체가 닿지 않아 timeout이 난 상태입니다. OKE에서 private Kubernetes API endpoint는 같은 VCN/연결된 네트워크에서 접근해야 하고, 필요하면 bastion을 통해 접근해야 합니다. 반대로 public endpoint를 쓸 때는 해당 endpoint 쪽에 적절한 접근 경로와 보안 규칙이 있어야 합니다.  ￼

지금 특히 중요한 점은, 앞서 kubectl은 138.2.121.171:6443로 붙으려 했고, Terraform은 10.0.30.148:6443로 붙으려 한다는 점입니다. 즉 kubectl과 Terraform provider가 서로 다른 API endpoint를 보고 있을 가능성이 큽니다. 이 상태에서는 kubeconfig는 public, Terraform은 private를 보는 식으로 꼬여서 둘 다 실패할 수 있습니다. kubeconfig는 oci ce cluster create-kubeconfig로 endpoint 타입을 지정해 다시 만들 수 있고, public endpoint를 쓸 때는 --kube-endpoint PUBLIC_ENDPOINT와 --token-version 2.0.0을 사용합니다.