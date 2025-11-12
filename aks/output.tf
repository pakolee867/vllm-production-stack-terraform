output "aks_deployment_info" {
  description = "Complete AKS deployment information"
  value = {
    cluster = {
      name        = module.aks.name
      resource_id = module.aks.resource_id
      fqdn        = module.aks.host
    }
    networking = {
      vnet = {
        id   = var.create_vnet ? module.vnet["vnet"].resource_id : var.vnet_id
        cidr = var.vnet_cidr
      }
      subnets = {
        system = {
          id   = local.system_subnet_id
          cidr = var.system_subnet
        }
        gpu = {
          id   = local.gpu_subnet_id
          cidr = var.gpu_subnet
        }
        appgw = {
          id   = local.appgw_subnet_id
          cidr = var.appgw_subnet
        }
      }
      kubernetes = {
        pod_cidr       = var.pod_cidr
        service_cidr   = var.service_cidr
        dns_service_ip = var.dns_service_ip
      }
    }
  }
  sensitive = true
}
 
output "grafana_url" {
  value = "https://${data.kubernetes_ingress_v1.grafana.spec[0].rule[0].host}"
}


# Output the complete API URL
output "vllm_api_url" {
  description = "The full HTTPS URL for the vLLM API"
  value = var.enable_vllm ? (
    local.vllm_ingress_host != "pending" && local.vllm_ingress_host != "not-deployed" 
    ? "https://${local.vllm_ingress_host}/v1"
    : local.vllm_ingress_host
  ) : null
  depends_on = [helm_release.vllm_stack]
}
 
#######################################################
# GPU Operator
#######################################################
output "gpu_operator_status" {
  description = "GPU Operator deployment status"
  value = lower(var.inference_hardware) == "gpu" ? {
    deployed  = true
    name      = helm_release.gpu_operator[0].name
    namespace = helm_release.gpu_operator[0].namespace
    version   = helm_release.gpu_operator[0].version
  } : {
    deployed = false
    reason   = "inference_hardware is not set to 'gpu'"
  }
}

# output "grafana_url" {
#   value = "https://grafana.${local.nginx_ip_hex}.nip.io"
# }
# output "grafana_forward_cmd" {
#   description = "Command to forward Grafana port"
#   value       = "kubectl get ingress/kube-prometheus-stack-grafana -n monitoring -o json | jq -r .spec.rules[].host"
# }

# In your root module (main.tf or outputs.tf)  
# output "aks" {  
#   description = "AKS cluster outputs"  
#   value       = module.aks  
#   sensitive   = true  
# }  

###############################################
#   Or expose specific outputs individually  
###############################################

# output "aks_kube_config" {  
#   description = "The kube_config block of the AKS cluster"  
#   value       = module.aks.kube_config  
#   sensitive   = true  
# }  
  
# output "aks_kube_admin_config" {  
#   description = "The kube_admin_config block of the AKS cluster"  
#   value       = module.aks.kube_admin_config  
#   sensitive   = true  
# }  
  
#############
# output "aks_host" {  
#   description = "AKS cluster API server host"  
#   value       = module.aks.host  
#   sensitive   = true  
# }  
  
# output "aks_cluster_ca_certificate" {  
#   description = "AKS cluster CA certificate"  
#   value       = module.aks.cluster_ca_certificate  
#   sensitive   = true  
# }


####################################
# RBAC and identity outputs
####################################

# Cluster identification outputs  
output "aks_name" {  
  description = "Name of the Kubernetes cluster"  
  value       = module.aks.name  
}  
  
output "aks_resource_id" {  
  description = "Resource ID of the Kubernetes cluster"  
  value       = module.aks.resource_id  
}  
  
# Identity outputs for RBAC  
output "aks_kubelet_identity_id" {  
  description = "The identity ID of the kubelet identity"  
  value       = module.aks.kubelet_identity_id  
}  
  
output "aks_key_vault_secrets_provider_object_id" {  
  description = "The object ID of the key vault secrets provider"  
  value       = module.aks.key_vault_secrets_provider_object_id  
}  
  
# Service integration outputs  
output "aks_oidc_issuer_url" {  
  description = "The OIDC issuer URL of the Kubernetes cluster"  
  value       = module.aks.oidc_issuer_url  
}  
# Output that defaults to null when no ingress exists  
# output "vllm_ingress_hostname" {  
#   description = "The hostname of the vLLM ingress load balancer (null if no ingress configured)"  
#   value = var.enable_vllm ? try(  
#     data.kubernetes_ingress_v1.vllm_ingress[0].status[0].load_balancer[0].ingress[0].hostname,  
#     null  # Explicitly return null if ingress doesn't exist or has no hostname  
#   ) : null  
#   depends_on = [helm_release.vllm_stack]  
# }  

# # Data source that only tries to read ingress if vLLM is enabled  
# data "kubernetes_ingress_v1" "vllm_ingress" {  
#   count = var.enable_vllm ? 1 : 0  

#   metadata {  
#     name      = "vllm-gpu-ingress-router"  # Adjust to match your actual ingress name  
#     namespace = kubernetes_namespace.vllm["vllm"].metadata[0].name  
#   }  

#   depends_on = [helm_release.vllm_stack]  
# }