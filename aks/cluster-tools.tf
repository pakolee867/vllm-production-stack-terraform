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
    # For Azure AKS with HTTP Application Routing
    { name = "ingressShim.defaultIssuerName", value = "letsencrypt-prod" },
    { name = "ingressShim.defaultIssuerKind", value = "ClusterIssuer" }
  ]

  depends_on = [module.aks]
}

# ClusterIssuer for Let's Encrypt with HTTP Application Routing  
resource "kubectl_manifest" "letsencrypt_issuer" {
  yaml_body = templatefile(
    "${path.module}/config/manifests/letsencrypt-issuer.yaml",
    { letsencrypt_email = var.letsencrypt_email }
  )
  depends_on = [helm_release.cert_manager]
}


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
        nginx_ip_hex          = local.nginx_ip_hex
        grafana_admin_password = var.grafana_admin_password
        # dns_prefix             = var.prefix
        # location               = var.location
      }
    )
  ]

  depends_on = [
    helm_release.cert_manager,          # cert-manager must be up first
    kubectl_manifest.letsencrypt_issuer, # ClusterIssuer must exist
    helm_release.nginx_ingress,      # NGINX Ingress must be ready
  ]
}

################################################################################
# 🛠️  GPU OPERATOR ADD-ON
################################################################################

# Adds the NVIDIA Operator to enable GPU access on vLLM pods  
resource "helm_release" "gpu_operator" {  
  count = lower(var.inference_hardware) == "gpu" ? 1 : 0  
  
  name       = "gpu-operator"  
  namespace  = "gpu-operator"  
  repository = "https://helm.ngc.nvidia.com/nvidia"  
  chart      = "gpu-operator"  
  version    = "v25.3.1"  
  
  values = [file(var.gpu_operator_file)]  
  
  create_namespace = true  
  wait             = true  
  
  depends_on = [module.aks]  
}