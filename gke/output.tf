output "Stack_Info" {
  value = "Built with ❤️ by @Cloudthrill"
}
output "gke_deployment_info" {
  description = "Complete GKE deployment information"
  value = {
    cluster = {
      name       = module.gke.name
      cluster_id = module.gke.cluster_id
      endpoint   = module.gke.endpoint
    }
    networking = {
      vpc = {
        id   = var.create_vpc ? module.vpc["vpc"].network_id : data.google_compute_network.existing[0].id
        name = local.vpc_name
      }
      subnet = {
        id   = var.create_vpc ? module.vpc["vpc"].subnets_self_links[0] : data.google_compute_subnetwork.existing[0].self_link
        cidr = var.subnetwork_cidr
      }
      kubernetes = {
        pod_cidr           = var.pod_cidr
        service_cidr       = var.service_cidr
        pod_range_name     = var.pod_range_name
        service_range_name = var.service_range_name
      }
    }
    project = {
      id = local.target_project_id
    }
  }
  sensitive = true
}

#######################################################  
#       Ingress EndPoints 
#######################################################  

output "grafana_url" {  
  value = "https://${data.kubernetes_ingress_v1.grafana.spec[0].rule[0].host}"  
}  

# # Output the complete API URL  
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
# GPU Driver Status (GKE handles this automatically)  
#######################################################  
output "gpu_driver_status" {
  description = "GPU driver installation status"
  value = lower(var.inference_hardware) == "gpu" ? {
    deployed = true
    method   = "GKE automatic installation"
    version  = "LATEST"
    reason   = "GKE handles GPU drivers automatically via gpu_driver_version parameter"
    } : {
    deployed = false
    reason   = "inference_hardware is not set to 'gpu'"
  }
}

####################################  
# Cluster identification outputs  
####################################  

output "gke_name" {
  description = "Name of the Kubernetes cluster"
  value       = module.gke.name
}

output "gke_cluster_id" {
  description = "Cluster ID of the GKE cluster"
  value       = module.gke.cluster_id
}

output "gke_location" {
  description = "Location (region/zone) of the GKE cluster"
  value       = module.gke.location
}

output "gke_region" {
  description = "Region of the GKE cluster"
  value       = module.gke.region
}

output "gke_master_version" {
  description = "Current master Kubernetes version"
  value       = module.gke.master_version
}

output "gke_endpoint" {
  description = "GKE cluster API server endpoint"
  value       = module.gke.endpoint
  sensitive   = true
}  
