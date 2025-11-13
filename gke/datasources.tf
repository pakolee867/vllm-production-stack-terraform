# # Get billing account from your existing project  
# data "google_project" "current" {  
#   project_id = var.project_id  # Your existing project ID from provider  
# }  
  
#######################################################  
#       Ingress EndPoints 
#######################################################

data "kubernetes_ingress_v1" "grafana" {
  metadata {
    name      = "${helm_release.kube_prometheus_stack.name}-grafana"
    namespace = helm_release.kube_prometheus_stack.namespace
  }
  
  depends_on = [helm_release.kube_prometheus_stack]
}

########################## 
# VLLM Ingress
##########################
# Data source to dynamically find the vLLM ingress created by the Helm chart
data "kubernetes_resources" "vllm_ingresses" {
  count = var.enable_vllm ? 1 : 0
  
  api_version = "networking.k8s.io/v1"
  kind        = "Ingress"
  namespace   = kubernetes_namespace.vllm["vllm"].metadata[0].name
  
  depends_on = [helm_release.vllm_stack]
}