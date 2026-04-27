# ──────────────────────────────────────────────────────────────
# OCI Services (Service Gateway용 cidr_block 조회)
# ──────────────────────────────────────────────────────────────
data "oci_core_services" "all" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

locals {
  svc_cidr = data.oci_core_services.all.services[0].cidr_block
  svc_id   = data.oci_core_services.all.services[0].id
}

# ──────────────────────────────────────────────────────────────
# VCN
# ──────────────────────────────────────────────────────────────
resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_id
  display_name   = "${var.prefix}-vcn"
  cidr_blocks    = [var.vcn_cidr]
  dns_label      = replace(var.prefix, "-", "")

  freeform_tags = var.tags
}

# ──────────────────────────────────────────────────────────────
# Gateways
# ──────────────────────────────────────────────────────────────
resource "oci_core_internet_gateway" "main" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.prefix}-igw"
  enabled        = true
  freeform_tags  = var.tags
}

resource "oci_core_nat_gateway" "main" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.prefix}-nat"
  block_traffic  = false
  freeform_tags  = var.tags
}

resource "oci_core_service_gateway" "main" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.prefix}-sgw"

  services {
    service_id = local.svc_id
  }

  freeform_tags = var.tags
}

# ──────────────────────────────────────────────────────────────
# Route Tables
# ──────────────────────────────────────────────────────────────
# Public RT: LB 서브넷 → Internet Gateway
resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.prefix}-rt-public"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.main.id
  }

  freeform_tags = var.tags
}

# Private RT: 워커/Pod 서브넷 → NAT + Service Gateway
resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.prefix}-rt-private"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.main.id
  }

  route_rules {
    destination       = local.svc_cidr
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.main.id
  }

  freeform_tags = var.tags
}

# ──────────────────────────────────────────────────────────────
# Security Lists
# ──────────────────────────────────────────────────────────────

# [1] LB 서브넷 Security List (Public)
resource "oci_core_security_list" "lb" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.prefix}-sl-lb"

  # Ingress: 인터넷 → HTTP/HTTPS
  ingress_security_rules {
    protocol  = "6" # TCP
    source    = "0.0.0.0/0"
    stateless = false
    tcp_options {
      min = 80
      max = 80
    }
  }
  ingress_security_rules {
    protocol  = "6"
    source    = "0.0.0.0/0"
    stateless = false
    tcp_options {
      min = 443
      max = 443
    }
  }

  # Egress: 워커 노드 NodePort (LB health check + 트래픽 전달)
  egress_security_rules {
    protocol    = "6"
    destination = var.worker_subnet_cidr
    stateless   = false
    tcp_options {
      min = 30000
      max = 32767
    }
  }
  egress_security_rules {
    protocol    = "6"
    destination = var.worker_subnet_cidr
    stateless   = false
    tcp_options {
      min = 10256
      max = 10256
    } # kube-proxy health check
  }

  freeform_tags = var.tags
}

# [2] API Endpoint 서브넷 Security List (Private)
resource "oci_core_security_list" "api" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.prefix}-sl-api"

  # Ingress: 워커 → API 6443 (kubectl/kubelet)
  ingress_security_rules {
    protocol  = "6"
    source    = var.worker_subnet_cidr
    stateless = false
    tcp_options {
      min = 6443
      max = 6443
    }
  }
  # Ingress: 워커 → OKE 서비스 포트 12250
  ingress_security_rules {
    protocol  = "6"
    source    = var.worker_subnet_cidr
    stateless = false
    tcp_options {
      min = 12250
      max = 12250
    }
  }
  # Ingress: 관리 CIDR(Bastion/VPN) → API 6443
  ingress_security_rules {
    protocol  = "6"
    source    = var.admin_cidr
    stateless = false
    tcp_options {
      min = 6443
      max = 6443
    }
  }
  # Ingress: 인터넷 → API 6443 (Public Endpoint 접근)
  ingress_security_rules {
    protocol  = "6"
    source    = "0.0.0.0/0"
    stateless = false
    tcp_options {
      min = 6443
      max = 6443
    }
  }
  # Ingress: ICMP Path MTU Discovery
  ingress_security_rules {
    protocol  = "1" # ICMP
    source    = var.worker_subnet_cidr
    stateless = false
    icmp_options {
      type = 3
      code = 4
    }
  }

  # Egress: API → 워커 kubelet 10250
  egress_security_rules {
    protocol    = "6"
    destination = var.worker_subnet_cidr
    stateless   = false
    tcp_options {
      min = 10250
      max = 10250
    }
  }
  # Egress: API → OCI Services (443)
  egress_security_rules {
    protocol         = "6"
    destination      = local.svc_cidr
    destination_type = "SERVICE_CIDR_BLOCK"
    stateless        = false
    tcp_options {
      min = 443
      max = 443
    }
  }
  # Egress: ICMP
  egress_security_rules {
    protocol    = "1"
    destination = var.worker_subnet_cidr
    stateless   = false
    icmp_options {
      type = 3
      code = 4
    }
  }

  freeform_tags = var.tags
}

# [3] Worker Node / VCN-native Pod 서브넷 Security List (Private egress)
resource "oci_core_security_list" "workers" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.prefix}-sl-workers"

  # Ingress: SSH (직접 접근 - bastion 불필요)
  ingress_security_rules {
    protocol  = "6"
    source    = "0.0.0.0/0"
    stateless = false
    tcp_options {
      min = 22
      max = 22
    }
  }
  # Ingress: LB → NodePort
  ingress_security_rules {
    protocol  = "6"
    source    = var.lb_subnet_cidr
    stateless = false
    tcp_options {
      min = 30000
      max = 32767
    }
  }
  # Ingress: LB → kube-proxy health check
  ingress_security_rules {
    protocol  = "6"
    source    = var.lb_subnet_cidr
    stateless = false
    tcp_options {
      min = 10256
      max = 10256
    }
  }
  # Ingress: API → kubelet 10250
  ingress_security_rules {
    protocol  = "6"
    source    = var.api_subnet_cidr
    stateless = false
    tcp_options {
      min = 10250
      max = 10250
    }
  }
  # Ingress: 노드 간 통신 (Pod-to-Pod, VCN-native)
  ingress_security_rules {
    protocol  = "all"
    source    = var.worker_subnet_cidr
    stateless = false
  }
  # Ingress: ICMP
  ingress_security_rules {
    protocol  = "1"
    source    = var.vcn_cidr
    stateless = false
    icmp_options {
      type = 3
      code = 4
    }
  }

  # Egress: API 서버 접근
  egress_security_rules {
    protocol    = "6"
    destination = var.api_subnet_cidr
    stateless   = false
    tcp_options {
      min = 6443
      max = 6443
    }
  }
  egress_security_rules {
    protocol    = "6"
    destination = var.api_subnet_cidr
    stateless   = false
    tcp_options {
      min = 12250
      max = 12250
    }
  }
  # Egress: 노드 간 통신
  egress_security_rules {
    protocol    = "all"
    destination = var.worker_subnet_cidr
    stateless   = false
  }
  # Egress: OCI Services (컨테이너 이미지 pull, OCI API 호출)
  egress_security_rules {
    protocol         = "6"
    destination      = local.svc_cidr
    destination_type = "SERVICE_CIDR_BLOCK"
    stateless        = false
    tcp_options {
      min = 443
      max = 443
    }
  }
  # Egress: 인터넷 (NAT를 통한 외부 이미지 pull, Git repo 접근 등)
  egress_security_rules {
    protocol    = "6"
    destination = "0.0.0.0/0"
    stateless   = false
  }

  # Egress: ArgoCD → 외부 Git repo (명시적 정책 — 0.0.0.0/0 룰과 별개로 박아둠)
  dynamic "egress_security_rules" {
    for_each = var.argocd_repo_endpoints
    content {
      protocol    = "6"
      destination = egress_security_rules.value.cidr
      stateless   = false
      tcp_options {
        min = egress_security_rules.value.port
        max = egress_security_rules.value.port
      }
    }
  }

  freeform_tags = var.tags
}

# ──────────────────────────────────────────────────────────────
# Subnets
# ──────────────────────────────────────────────────────────────

# LB 서브넷 (Public)
resource "oci_core_subnet" "lb" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.main.id
  display_name               = "${var.prefix}-subnet-lb"
  cidr_block                 = var.lb_subnet_cidr
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.lb.id]
  prohibit_public_ip_on_vnic = false
  dns_label                  = "lbsubnet"
  freeform_tags              = var.tags
}

# 워커 노드 / VCN-native Pod 서브넷
#
# OKE VCN-native Pod IP는 이 서브넷의 사설 IP(10.0.20.x)를 직접 사용한다.
# Pod 사설 IP는 IGW 경유 인터넷 egress가 되지 않으므로 NAT 라우팅이 필요하다.
resource "oci_core_subnet" "workers" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.main.id
  display_name               = "${var.prefix}-subnet-workers"
  cidr_block                 = var.worker_subnet_cidr
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.workers.id]
  prohibit_public_ip_on_vnic = false
  dns_label                  = "workersnet"
  freeform_tags              = var.tags
}

# API Endpoint 서브넷 (Public - OKE Public Endpoint용)
resource "oci_core_subnet" "api" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.main.id
  display_name               = "${var.prefix}-subnet-api"
  cidr_block                 = var.api_subnet_cidr
  route_table_id             = oci_core_route_table.public.id # IGW 경유로 변경
  security_list_ids          = [oci_core_security_list.api.id]
  prohibit_public_ip_on_vnic = false # Public IP 허용
  dns_label                  = "apisubnet"
  freeform_tags              = var.tags
}
