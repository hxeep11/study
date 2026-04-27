# ──────────────────────────────────────────────────────────────
# OKE Terraform Makefile
# 작업 위치 : /root/study/oci-tf/Makefile
# 사용법:
#   make init         - provider 초기화
#   make plan-infra   - Step-1 plan (network + OKE)
#   make apply-infra  - Step-1 apply (network + OKE)
#   make plan         - Step-2 plan (전체)
#   make apply        - Step-2 apply (Helm addons 포함)
#   make destroy      - 안전한 순서로 전체 삭제
#   make kubeconfig   - kubeconfig 생성
# ──────────────────────────────────────────────────────────────

.PHONY: init plan-iam apply-iam plan-infra apply-infra plan apply destroy kubeconfig fmt validate

TFVARS := terraform.tfvars

init:
	terraform init -upgrade

fmt:
	terraform fmt -recursive

validate: init
	terraform validate

# ── Step-0: IAM (Dynamic Group + Policy) 먼저 배포 ───────────
# module.oke 와 분리하여 독립 재시도 가능
# 이미 존재하는 경우: terraform import 후 재실행하거나 lifecycle ignore_changes로 통과
plan-iam:
	terraform plan \
	  -target=module.iam \
	  -var-file=$(TFVARS) \
	  -out=tfplan-iam

apply-iam:
	@echo "⏳ 기존 IAM 리소스 state import 확인 중 (409 방지)..."
	@bash scripts/import_iam.sh $(TFVARS)
	terraform apply tfplan-iam
	@echo "✅ Step-0 완료: IAM Dynamic Group + Policy 배포 성공"

# ── Step-1: 인프라(네트워크 + OKE) 먼저 배포 ──────────────────
plan-infra:
	terraform plan \
	  -target=module.network \
	  -target=module.oke \
	  -var-file=$(TFVARS) \
	  -out=tfplan-infra

apply-infra:
	terraform apply tfplan-infra
	@echo "✅ Step-1 완료: network + OKE 배포 성공"
	@echo "   → kubeconfig 생성 후 Step-2를 실행하세요: make kubeconfig && make apply"

# Out of host capacity 발생 시 자동 재시도 (2분 간격)
retry-infra:
	@bash $(CURDIR)/../retry_apply.sh

# ── Step-2: Helm Addons (NGINX IC + ArgoCD + Prometheus) 배포 ─
plan:
	terraform apply -refresh-only -var-file=$(TFVARS) -auto-approve
	terraform plan -var-file=$(TFVARS) -out=tfplan

apply:
	terraform apply tfplan
	@echo ""
	@echo "✅ Step-2 완료: Helm Addons 배포 성공"
	@LB_IP=$$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending"); \
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; \
	echo "🌐 NGINX Ingress LB : $$LB_IP"; \
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; \
	echo "🔷 ArgoCD           : http://$$LB_IP/"; \
	echo "👤 ArgoCD User      : admin"; \
	echo "🔑 ArgoCD Pass      : terraform output -raw argocd_admin_password"; \
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; \
	echo "📊 Grafana          : http://$$LB_IP/grafana"; \
	echo "👤 Grafana User     : admin"; \
	echo "🔑 Grafana Pass     : terraform output -raw grafana_admin_password"; \
	echo "📈 Prometheus       : kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090"; \
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

show-info:
	@LB_IP=$$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending"); \
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; \
	echo "🌐 NGINX Ingress LB : $$LB_IP"; \
	echo "📋 kubectl context  : $$(kubectl config current-context)"; \
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; \
	echo "🔷 ArgoCD           : http://$$LB_IP/"; \
	echo "👤 ArgoCD User      : admin"; \
	echo "🔑 ArgoCD Pass      : $$(terraform output -raw argocd_admin_password 2>/dev/null || echo 'run: terraform output -raw argocd_admin_password')"; \
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; \
	echo "📊 Grafana          : http://$$LB_IP/grafana"; \
	echo "👤 Grafana User     : admin"; \
	echo "🔑 Grafana Pass     : $$(terraform output -raw grafana_admin_password 2>/dev/null || echo 'run: terraform output -raw grafana_admin_password')"; \
	echo "📈 Prometheus       : kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090"; \
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Full 배포 (처음 실행 또는 CI/CD 환경) ─────────────────────
apply-all:
	$(MAKE) plan-iam
	$(MAKE) apply-iam
	$(MAKE) apply-infra
	$(MAKE) kubeconfig
	@echo "⏳ 노드 Ready 대기 중 (60초)..."
	@sleep 60
	$(MAKE) plan
	$(MAKE) apply

# ── kubeconfig 생성 ────────────────────────────────────────────
kubeconfig:
	@CLUSTER_ID=$$(terraform output -raw cluster_id) && \
	REGION=$$(terraform output -raw region 2>/dev/null || grep '^region' $(TFVARS) | awk -F'"' '{print $$2}') && \
	oci ce cluster create-kubeconfig \
	  --cluster-id $$CLUSTER_ID \
	  --region $$REGION \
	  --token-version 2.0.0 \
	  --kube-endpoint PRIVATE_ENDPOINT \
	  --file ~/.kube/config
	@echo "✅ kubeconfig 생성: ~/.kube/config"

# ── 안전한 순서 Destroy ────────────────────────────────────────
destroy:
	@bash scripts/destroy.sh

# ── Orphan Private IP 정리 ─────────────────────────────────────
# LB/VNIC 삭제 후 서브넷에 남은 찌꺼기 private IP 회수
#   make cleanup-ips             # LB 서브넷만
#   make cleanup-ips SCOPE=all   # LB + workers + api
#   make cleanup-ips DRY_RUN=1   # 후보만 출력
cleanup-ips:
	@DRY_RUN=$(DRY_RUN) bash scripts/cleanup_private_ips.sh $(or $(SCOPE),lb)
