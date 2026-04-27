# ──────────────────────────────────────────
# OCI Provider
# ──────────────────────────────────────────
# 1. 춘천 기본 프로바이더 (기존 설정 활용)
provider "oci" {
  region = var.region
  # config_file_location = "/root/.oci/config"
  config_file_profile = "DEFAULT"
}

# 2. 서울 홈 리전 프로바이더 (경로를 직접 지정하여 401 에러 원천 차단)
provider "oci" {
  alias  = "home"
  region = "ap-chuncheon-1"
  # config_file_location = "/root/.oci/config" # 👈 신분증 위치를 절대경로로 명시
  config_file_profile = "DEFAULT"
}

# ──────────────────────────────────────────
# Kubernetes / Helm Provider
#
# [주의] Private API Endpoint 사용 시:
#   - terraform apply를 실행하는 호스트가 반드시 VCN 내부(Bastion)
#     또는 VPN/FastConnect를 통해 OKE API에 접근 가능해야 합니다.
#   - Step-1 (network+oke) 적용 후 Step-2 (helm-addons) 적용하세요.
#
# OCI CLI exec 플러그인으로 토큰을 자동 갱신합니다.
# 전제 조건: `oci` CLI 설치 및 설정 완료
# ──────────────────────────────────────────
provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes = {
    config_path = "~/.kube/config"
  }
}
