# ──────────────────────────────────────────────────────────────
# Namespace 생성
# ──────────────────────────────────────────────────────────────
resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name   = "argocd"
    labels = { "app.kubernetes.io/managed-by" = "terraform" }
  }
}

# ──────────────────────────────────────────────────────────────
# [1] NGINX Ingress Controller (Helm)
#
# - OCI CCM이 LoadBalancer 서비스를 감지해 OCI LB를 자동 프로비저닝
# - 이 LB 하나로 ArgoCD + Grafana 모두 라우팅 (path 기반)
# - Admission Webhook 비활성화: 동시 배포 시 타이밍 문제 방지
# ──────────────────────────────────────────────────────────────
resource "kubernetes_namespace_v1" "nginx_ingress" {
  metadata {
    name   = "ingress-nginx"
    labels = { "app.kubernetes.io/managed-by" = "terraform" }
  }
}

resource "helm_release" "nginx_ingress" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = kubernetes_namespace_v1.nginx_ingress.metadata[0].name
  version          = var.nginx_ingress_chart_version
  create_namespace = false
  atomic           = true
  timeout          = 300

  values = [
    yamlencode({
      controller = {
        ingressClassResource = {
          default = true
        }

        service = {
          type = "LoadBalancer"
          annotations = {
            "service.beta.kubernetes.io/oci-load-balancer-shape"          = "flexible"
            "service.beta.kubernetes.io/oci-load-balancer-shape-flex-min" = "10"
            "service.beta.kubernetes.io/oci-load-balancer-shape-flex-max" = "10"
            "service.beta.kubernetes.io/oci-load-balancer-subnet1"        = var.lb_subnet_id
          }
        }

        resources = {
          requests = { cpu = "100m", memory = "128Mi" }
          limits   = { cpu = "500m", memory = "256Mi" }
        }

        admissionWebhooks = {
          enabled = false
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace_v1.nginx_ingress]
}

# ──────────────────────────────────────────────────────────────
# [2] ArgoCD (Helm)
#
# - ClusterIP + NGINX Ingress (/argocd sub-path)
# - rootpath + insecure: Ingress 뒤 HTTP, sub-path 하에서 auth/redirect 정상
# - 전용 OCI LB 불필요 → NGINX Ingress LB 공유
# ──────────────────────────────────────────────────────────────
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = kubernetes_namespace_v1.argocd.metadata[0].name
  version          = var.argocd_chart_version
  create_namespace = true
  atomic           = true
  timeout          = 600
  wait             = true
  wait_for_jobs    = true

  values = [
    yamlencode({
      global = {
        nodeSelector = {}
      }

      configs = {
        secret = {
          argocdServerAdminPassword      = "$2b$10$DateHlMNoULFg./Bm4fpeuQngL0d7Vwt.xfnnnh1yUnxv7bMVdfsa"
          argocdServerAdminPasswordMtime = "2025-01-01T00:00:00Z"
        }
        params = {
          "server.rootpath" = "/argocd"
          "server.insecure" = true
        }
      }

      server = {
        service = {
          type = "ClusterIP"
        }
        # 차트 내장 ingress는 hostname 비면 argocd.example.com을 강제로 박아
        # host-less 라우팅 불가 → 아래 kubernetes_ingress_v1.argocd로 대체
        ingress = {
          enabled = false
        }
      }

      repoServer = {
        resources = {
          requests = { cpu = "100m", memory = "256Mi" }
          limits   = { cpu = "500m", memory = "512Mi" }
        }
      }

      applicationSet = {
        resources = {
          requests = { cpu = "50m", memory = "128Mi" }
          limits   = { cpu = "200m", memory = "256Mi" }
        }
      }

      redis = {
        resources = {
          requests = { cpu = "50m", memory = "64Mi" }
          limits   = { cpu = "200m", memory = "128Mi" }
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace_v1.argocd,
    helm_release.nginx_ingress,
  ]
}

# ──────────────────────────────────────────────────────────────
# [3] kube-prometheus-stack (Helm)
#
# - Grafana: NGINX Ingress /grafana sub-path로 노출
# - Prometheus / Alertmanager: ClusterIP (내부 전용)
# - LB 추가 불필요 → NGINX Ingress LB 공유
# ──────────────────────────────────────────────────────────────
resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name   = "monitoring"
    labels = { "app.kubernetes.io/managed-by" = "terraform" }
  }
}

resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = kubernetes_namespace_v1.monitoring.metadata[0].name
  version          = var.prometheus_stack_chart_version
  create_namespace = false
  atomic           = true
  timeout          = 600
  wait             = true

  values = [
    yamlencode({
      # ── Grafana ──────────────────────────────────────────────
      grafana = {
        enabled = true

        adminPassword = var.grafana_admin_password

        # /grafana sub-path 설정
        "grafana.ini" = {
          server = {
            root_url            = "%(protocol)s://%(domain)s/grafana"
            serve_from_sub_path = true
          }
        }

        service = {
          type = "ClusterIP"
          port = 3000
        }

        ingress = {
          enabled          = true
          ingressClassName = "nginx"
          path             = "/grafana"
          pathType         = "Prefix"
          # host 미지정 → LB IP/grafana 로 직접 접근 가능
        }

        resources = {
          requests = { cpu = "100m", memory = "128Mi" }
          limits   = { cpu = "500m", memory = "256Mi" }
        }
      }

      # ── Prometheus ───────────────────────────────────────────
      prometheus = {
        prometheusSpec = {
          retention = "7d"

          externalLabels = {
            cluster = "${var.prefix}-oke"
          }

          resources = {
            requests = { cpu = "200m", memory = "512Mi" }
            limits   = { cpu = "1", memory = "1Gi" }
          }

          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                accessModes = ["ReadWriteOnce"]
                resources = {
                  requests = { storage = "20Gi" }
                }
              }
            }
          }
        }

        service = {
          type = "ClusterIP"
          port = 9090
        }
        # 차트 ingress 비활성화 → 아래 kubernetes_ingress_v1.prometheus로 대체
        ingress = {
          enabled = false
        }
      }

      # ── Alertmanager ─────────────────────────────────────────
      alertmanager = {
        alertmanagerSpec = {
          resources = {
            requests = { cpu = "50m", memory = "64Mi" }
            limits   = { cpu = "200m", memory = "128Mi" }
          }
        }

        service = {
          type = "ClusterIP"
          port = 9093
        }
      }

      # ── Node Exporter ────────────────────────────────────────
      nodeExporter = {
        resources = {
          requests = { cpu = "50m", memory = "32Mi" }
          limits   = { cpu = "200m", memory = "64Mi" }
        }
      }

      # ── kube-state-metrics ───────────────────────────────────
      kube-state-metrics = {
        resources = {
          requests = { cpu = "50m", memory = "64Mi" }
          limits   = { cpu = "200m", memory = "128Mi" }
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace_v1.monitoring,
    helm_release.nginx_ingress,
  ]
}

# ──────────────────────────────────────────────────────────────
# [4] Ingress: ArgoCD (/argocd) — host-less, LB IP 직접 접속용
# ──────────────────────────────────────────────────────────────
resource "kubernetes_ingress_v1" "argocd" {
  metadata {
    name      = "argocd-server"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
    annotations = {
      "nginx.ingress.kubernetes.io/ssl-redirect" = "false"
    }
  }

  spec {
    ingress_class_name = "nginx"
    rule {
      http {
        path {
          path      = "/argocd"
          path_type = "Prefix"
          backend {
            service {
              name = "argocd-server"
              port { number = 80 }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.argocd]
}

# ──────────────────────────────────────────────────────────────
# [5] Ingress: Prometheus (/prometheus)
# ──────────────────────────────────────────────────────────────
resource "kubernetes_ingress_v1" "prometheus" {
  metadata {
    name      = "prometheus"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
    annotations = {
      "nginx.ingress.kubernetes.io/ssl-redirect"   = "false"
      "nginx.ingress.kubernetes.io/rewrite-target" = "/$2"
    }
  }

  spec {
    ingress_class_name = "nginx"
    rule {
      http {
        path {
          path      = "/prometheus(/|$)(.*)"
          path_type = "ImplementationSpecific"
          backend {
            service {
              name = "kube-prometheus-stack-prometheus"
              port { number = 9090 }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.kube_prometheus_stack]
}

# ──────────────────────────────────────────────────────────────
# [6] Root path redirect: `/` → `/argocd/`
#
# - LB IP 직접 접속 시 ArgoCD로 308 리다이렉트
# - backend는 필수 필드 충족용 (리다이렉트가 먼저 발생)
# ──────────────────────────────────────────────────────────────
resource "kubernetes_ingress_v1" "root_redirect" {
  metadata {
    name      = "root-redirect"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
    annotations = {
      "nginx.ingress.kubernetes.io/permanent-redirect"      = "/argocd/"
      "nginx.ingress.kubernetes.io/permanent-redirect-code" = "308"
      "nginx.ingress.kubernetes.io/ssl-redirect"            = "false"
    }
  }

  spec {
    ingress_class_name = "nginx"
    rule {
      http {
        path {
          path      = "/"
          path_type = "Exact"
          backend {
            service {
              name = "argocd-server"
              port { number = 80 }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.argocd]
}

# ──────────────────────────────────────────────────────────────
# ArgoCD 초기 Admin 패스워드 조회
# ──────────────────────────────────────────────────────────────
data "kubernetes_secret_v1" "argocd_initial_password" {
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
  }

  depends_on = [helm_release.argocd]
}
