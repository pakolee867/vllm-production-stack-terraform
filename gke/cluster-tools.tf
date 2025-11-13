#cluster-tools.tf

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = "cert-manager"
  version    = "v1.15.5"

  create_namespace = true
  set = [
    { name = "installCRDs", value = "true" },
    # For Azure GKE with HTTP Application Routing
    { name = "ingressShim.defaultIssuerName", value = "letsencrypt-prod" },
    { name = "ingressShim.defaultIssuerKind", value = "ClusterIssuer" }
  ]

  depends_on = [module.gke]
}

# ClusterIssuer for Let's Encrypt with HTTP Application Routing  
resource "kubectl_manifest" "letsencrypt_issuer" {
  yaml_body = templatefile(
    "${path.module}/config/manifests/letsencrypt-issuer.yaml",
    { 
      letsencrypt_email = var.letsencrypt_email 
      static_ip_name    = google_compute_global_address.ingress_ip.name
    }
  )
  depends_on = [
    helm_release.cert_manager,
    google_compute_global_address.ingress_ip,
    google_compute_router_nat.nat,
  ]
}
  
     # 
###################################################################
# Metrics Server for Kubernetes
###################################################################
# not needed built in
# resource "helm_release" "metrics_server" {  
#   count      = var.enable_metrics_server ? 1 : 0  
#   name       = "metrics-server"  
#   repository = "https://kubernetes-sigs.github.io/metrics-server/"  
#   chart      = "metrics-server"  
#   namespace  = "kube-system"  
    
#   depends_on = [module.gke]  
# }


##########################
# Observability Stack
##########################

resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "kube-prometheus-stack" #
  version          = "75.15.0"
  create_namespace = true

  values = [
    templatefile(
      "${path.module}/config/helm/kube-prome-stack.yaml",
      {
        ingress_ip_hex         = local.ingress_ip_hex  # Match ip hex value for sslip.io domain
        grafana_admin_password = var.grafana_admin_password
        static_ip_name          = google_compute_global_address.ingress_ip.name   
      }
    )
  ]

  depends_on = [
    helm_release.cert_manager,          # cert-manager must be up first
    kubectl_manifest.letsencrypt_issuer, # ClusterIssuer must exist
    google_compute_global_address.ingress_ip
  ]
}

output "LB-IP-Address" {
  value = google_compute_global_address.ingress_ip.address
}


################################################################################
# 🛠️  GPU OPERATOR ADD-ON
################################################################################

