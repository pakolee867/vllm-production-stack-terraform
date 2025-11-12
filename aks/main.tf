## -------------------------------------------------------------------------------------------
##  Author: Kosseila HD (@CloudThrill)
##  License: MIT
##  Date: Summer 2025
##  Description: Infrastructure as Code for vLLM in AKS with azure cilium CNI, Cert-Manager,
##               TLS via Let's Encrypt, and observability stack (Grafana, Prometheus).
##
##  Part of the CloudThrill Kubernetes contribution to lm-cache vLLM production-stack project.     
##  https://cloudthrill.ca
## -------------------------------------------------------------------------------------------
################################################################################
resource "azurerm_resource_group" "rg" {
  location = var.location
  name     = "${var.prefix}-rg"
}
################################################################################
# Dynamic node-group map (CPU mandatory, GPU optional)
################################################################################
locals {
  # Define base CPU pool (always present for default node pool)    
  base_cpu_pool = {
    cpu = {
      name                 = "cpu-pool"
      vm_size              = "Standard_D4s_v4" # Standard_D4as_v6/v3 # 4 vCPU, 16 GiB RAM AMD EPYC
      orchestrator_version = var.cluster_version
      max_count            = var.cpu_node_max_size
      min_count            = var.cpu_node_min_size
      os_disk_size_gb      = var.cpu_os_disk_size_gb # Using your variable (50 GB)  
      os_disk_type         = var.cpu_os_disk_type    # Using your variable ("Ephemeral")  
      os_sku               = var.cpu_os_sku          # Using your variable ("AzureLinux")
      # mode                 = "User"   # Default mode for AKS node pools is "User"
      labels = {
        "workload-type" = "cpu"
        "node-group"    = "cpu-pool"
      }
    }
  }


  # Define GPU pool with node_taints included  
  gpu_pool = {
    gpu = {
      name                 = "gpu"
      vm_size              = "Standard_NC4as_T4_v3" #"Standard_NC6s_v3"  Tesla V100 16GB vRAM
      orchestrator_version = var.cluster_version
      max_count            = var.gpu_node_max_size
      min_count            = var.gpu_node_min_size
      os_disk_size_gb      = var.gpu_os_disk_size_gb # (100 GB)  
      os_disk_type         = var.gpu_os_disk_type    # ("Ephemeral") if VM supports it like Standard_D8s_v4 support  
      os_sku               = var.gpu_os_sku          # Using your variable ("AzureLinux")
      vnet_subnet_id       = local.gpu_subnet_id     # Add this         
      # mode                 = "User"  
      labels = {
        "workload-type" = "gpu"
        "node-group"    = "gpu-pool"
      }
      # Add node_taints to the local configuration  
      node_taints = ["nvidia.com/gpu=Exists:NoSchedule"]
    }
  }

  # Merge pools based on inference hardware    
  all_node_pools = merge(
    local.base_cpu_pool,
    lower(var.inference_hardware) == "gpu" ? local.gpu_pool : {}
  )
}
################################################################################
# AKS Cluster Module
################################################################################
module "aks" {
  source = "./modules/avm-res-cs-managedcluster" # Changed from avm-ptn-aks-production  

  # Basic configuration    
  location              = var.location
  name                  = var.prefix
  resource_group_name   = azurerm_resource_group.rg.name
  kubernetes_version    = var.cluster_version
  dns_prefix            = var.prefix # for public clusters 
  run_command_enabled   = var.run_command_enabled
  local_account_disabled = false 
  image_cleaner_enabled = var.image_cleaner_enabled
  image_cleaner_interval_hours     = var.image_cleaner_interval_hours 
  
  # DNS configuration
  # Private cluster with public FQDN  
  # private_cluster_enabled             = true  
  # private_cluster_public_fqdn_enabled = true  
  # dns_prefix_private_cluster       = var.prefix  # when private_cluster_public_fqdn_enabled = true


  # System-assigned identity with necessary permissions for cluster operations.
  managed_identities = {
    system_assigned = true
    #OR user_assigned_resource_ids = ["user-assigned-id"]  
  }

  # Default node pool configuration (using CPU values)    
  default_node_pool = {
    name                 = "system"
    vm_size              = local.base_cpu_pool.cpu.vm_size
    orchestrator_version = var.cluster_version
    max_count            = var.cpu_node_max_size
    min_count            = var.cpu_node_min_size
    os_disk_size_gb      = var.cpu_os_disk_size_gb
    os_disk_type         = var.cpu_os_disk_type
    os_sku               = var.cpu_os_sku
    auto_scaling_enabled = true
    node_labels          = local.base_cpu_pool.cpu.labels
    vnet_subnet_id       = local.system_subnet_id
  }

  # Network configuration    
  network_profile = {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"  
    network_policy      = var.network_policy # calico (defaults to cilium) 
    outbound_type       = var.outbound_type  # "loadBalancer" | "userDefinedRouting" | "managedNATGateway" | "userAssignedNATGateway"
    pod_cidr            = var.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = local.network_config.dns_service_ip  # dns_service_ip must be placed within your service_cidr range
   # load_balancer_sku   = "standard"  # Required for load_balancer_profile  
   # load_balancer_profile = {   
   #     managed_outbound_ip_count = 2  
   #     idle_timeout_in_minutes   = 30  
   #     outbound_ports_allocated  = 8000  
   #   }
   
  }

  # Application routing and cluster features   
  # http_application_routing_enabled = true  (is deprecated)
  #   ingress_application_gateway = {  
  #     gateway_name = "aks-appgw"  
  #     subnet_id    = local.appgw_subnet_id  # Your existing AppGW subnet  
  #     # subnet_cidr  = var.appgw_subnet  # "10.20.50.0/24"  # Your appgw_subnet variable  
  #   }  

  # Storage configuration
  storage_profile = {
    disk_driver_enabled = var.enable_disk_csi_driver # Azure Disk CSI driver  
    file_driver_enabled = var.enable_file_csi_driver # Azure File CSI driver  
    snapshot_controller_enabled = false
    # blob_driver_enabled         = var.enable_blob_driver   # Optional: Azure Blob CSI driver  
  }

  linux_profile = {
    admin_username = "azureuser"
    ssh_key        = file("~/.ssh/id_rsa.pub") # Use existing key  
  }


  # GPU node pool configuration - conditionally added  
  node_pools = lower(var.inference_hardware) == "gpu" ? {
    gpu = {
      name                 = local.gpu_pool.gpu.name
      vm_size              = local.gpu_pool.gpu.vm_size
      orchestrator_version = local.gpu_pool.gpu.orchestrator_version
      auto_scaling_enabled = true
      max_count            = local.gpu_pool.gpu.max_count
      min_count            = local.gpu_pool.gpu.min_count
      os_disk_size_gb      = local.gpu_pool.gpu.os_disk_size_gb
      os_disk_type         = local.gpu_pool.gpu.os_disk_type
      os_sku               = local.gpu_pool.gpu.os_sku
      vnet_subnet_id       = local.gpu_subnet_id
      node_labels          = local.gpu_pool.gpu.labels
      node_taints          = local.gpu_pool.gpu.node_taints
    }
  } : {}

  # Workload autoscaling  
  workload_autoscaler_profile = {
    keda_enabled = var.enable_keda
    vpa_enabled  = var.enable_vpa
  }

  # Security and RBAC     
  azure_active_directory_role_based_access_control = {
    azure_rbac_enabled = var.rbac_aad_azure_rbac_enabled
    tenant_id          = var.tenant_id
    # rbac_aad_admin_group_object_ids = var.rbac_aad_admin_group_object_ids 

  }

  # OIDC and Workload Identity  
  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  enable_telemetry          = false

  # Tags    
  tags = var.tags
}

########################################
# Kubernetes kubeconfig file
########################################
resource "local_file" "kubeconfig" {  
  content = templatefile("${path.module}/config/kubeconfig.tpl", {  
    cluster_name             = module.aks.name  
    cluster_endpoint         = module.aks.host  
    cluster_ca               = module.aks.cluster_ca_certificate[0].cluster_ca_certificate  
    admin_client_certificate = module.aks.kube_admin_config[0].client_certificate  
    admin_client_key         = module.aks.kube_admin_config[0].client_key  
  })  
  filename             = "${path.module}/kubeconfig"  
  file_permission      = "0600"  
  directory_permission = "0755"  
    
  depends_on = [module.aks]  
}