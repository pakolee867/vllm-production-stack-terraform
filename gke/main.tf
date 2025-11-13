## -------------------------------------------------------------------------------------------
##  Author: Kosseila HD (@CloudThrill)
##  License: MIT
##  Date: Summer 2025
##  Description: Infrastructure as Code for vLLM in GKE with azure cilium CNI, Cert-Manager,
##               TLS via Let's Encrypt, and observability stack (Grafana, Prometheus).
##
##  Part of the CloudThrill Kubernetes contribution to lm-cache vLLMproduction-stack project.     
##  https://cloudthrill.ca
## -------------------------------------------------------------------------------------------
################################################################################
# Project logic: ensures the proper creation order: Project → APIs → VPC → GKE cluster, preventing the API enablement errors.
################################################################################
# GCP Project (Optional)  
################################################################################

# Get billing account from your existing project  
data "google_project" "current" {
  project_id = var.project_id # Your existing project ID from provider  
}
# Conditional API enablement for existing projects  
resource "google_project_service" "existing_project_services" {  
  for_each = var.create_project ?  toset([]) : toset(var.gcp_services)  
    
  project = var.project_id  # The existing project  
  service = each.value  
  ### keeps APIs from being disabled when the resource is destroyed.  (resource itself will still be removed from tfstate). 
  disable_on_destroy = false  
  disable_dependent_services = false  
  
}  

################################################
# Project Factory Module
################################################
# if create_project is true, This module creates a new GCP project with the specified name and ID, and sets up
resource "random_id" "project_suffix" {
  count       = var.create_project ? 1 : 0
  byte_length = 4
}
 
module "vllm_gke_project" {
  count  = var.create_project ? 1 : 0
  source = "./modules/google-project-factory"

  name            = "vllm-gke"
  project_id      = "vllm-gke-${random_id.project_suffix[0].hex}"
  billing_account = data.google_project.current.billing_account
  org_id          = data.google_project.current.org_id
  activate_apis   = var.gcp_services

  auto_create_network = false
}

# Local to determine which project ID to use  
locals {
  target_project_id = var.create_project ? module.vllm_gke_project[0].project_id : var.project_id
}


################################################################################
# Dynamic node-group map (CPU mandatory, GPU optional)
################################################################################
locals {
  # --- 1️⃣ CPU pool (always present) ---  
  base_cpu_pool = [
    {
      name               = "cpu-pool"
      machine_type       = "n2-standard-4" # 4 vCPU, 16 GiB RAM | support avx512 instructions (c3-standard-4)  
      min_count          = var.cpu_node_min_size
      max_count          = var.cpu_node_max_size
      initial_node_count = var.cpu_node_min_size
      disk_size_gb       = var.cpu_os_disk_size_gb
      disk_type          = var.cpu_disk_type
      image_type         = var.os_image_type
      accelerator_count  = "0"     # Set to 0 for CPU-only pools  
      accelerator_type   = ""    # Empty string for CPU pools  
      gpu_driver_version = ""    # Empty string for CPU pools  
      auto_repair        = true
      auto_upgrade       = true
      preemptible        = false
      spot               = false 
   #   zones              = join(",", local.selected_zones)
    }
  ]

  # --- 2️⃣ GPU pool (conditional) ---  
  gpu_pool = [
    {
      name               = "gpu-pool"
      machine_type       = "g2-standard-4" # "n1-standard-4"  
      min_count          = var.gpu_node_min_size
      max_count          = var.gpu_node_max_size
      initial_node_count = var.gpu_node_min_size
      disk_size_gb       = var.gpu_os_disk_size_gb
      disk_type          = var.gpu_disk_type
      image_type         = var.os_image_type
      accelerator_count  = "1"
      accelerator_type   = "nvidia-l4" # "nvidia-tesla-t4"
      gpu_driver_version = "LATEST"
      auto_repair        = true
      auto_upgrade       = true
      preemptible        = false
      spot               = true # Similar to your SPOT capacity_type  
    #  zones              = join(",", local.gpu_zones)  # Convert list to comma-separated string
    }
  ]

  # --- 3️⃣ Final node pools list ---  
  node_pools_list = concat(
    local.base_cpu_pool,
    lower(var.inference_hardware) == "gpu" ? local.gpu_pool : []
  )
}
################################################################################
# GKE Cluster Module
################################################################################
module "gke" {
  source = "./modules/private-cluster-update-variant"

  project_id          = local.target_project_id
  name                = var.cluster_name
  region              = var.region
  regional            = var.regional  # Make it zonal instead of regional  
  zones               = local.selected_zones
  network             = local.network_config.network
  subnetwork          = local.network_config.subnetwork
  ip_range_pods       = var.pod_range_name
  ip_range_services   = var.service_range_name
  kubernetes_version  = var.cluster_version
  deletion_protection = false
  remove_default_node_pool = true

  # Private cluster configuration   
  enable_private_nodes    = var.enable_private_nodes
  enable_private_endpoint = var.enable_private_endpoint
  master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  # Overlay CNI configuration (equivalent to Azure overlay mode)  
  datapath_provider = "ADVANCED_DATAPATH" # Enables eBPF-based overlay networking    
  network_policy    = false               # Dataplane V2 handles network policies natively. True to Enable network policy addon   
  # network_policy_provider = "CILIUM"  # Use Cilium/Calico for advanced network policies (optional)
  # Basic addons  
  http_load_balancing             = true
  horizontal_pod_autoscaling      = true # default is true, but set to false if not needed
  enable_vertical_pod_autoscaling = var.enable_vpa


  # CSI drivers  
  gce_pd_csi_driver    = var.enable_disk_csi_driver
  filestore_csi_driver = var.enable_file_csi_driver
  # Disable cost-incurring features that default to true  
  enable_resource_consumption_export = false # defaults to true
  enable_shielded_nodes              = true  # defaults to true incur minor costs on Cloud loggings due to more logging data (~ 0.5 KB more per startup) than standard nodes, which may incur minor costs based on Cloud Logging's pricing. 
  # enable_confidential_nodes              = false  # defaults to false, but set to true if using confidential VMs
  # sandbox_enabled                         = false  # Beta module Only : enable gVisor when `image_type` = `COS_CONTAINERD`
  enable_identity_service = false # defaults to false  allows customers to use external identity providers with the K8S API."
  # enable_secret_manager_addon = false  # defaults to true, but set to false if not using Secret Manager
  # boot_disk_kms_key = "projects/..." # if you want CMEK encryption for the boot disk   

  # Ensure managed monitoring features stay disabled  
  monitoring_enable_managed_prometheus    = false
  monitoring_enable_observability_metrics = false
  monitoring_enable_observability_relay   = false


  # Node pools  
  node_pools = local.node_pools_list

  # Node pool labels  
  node_pools_labels = {
    all = {}
    cpu-pool = {
      "workload-type" = "cpu"
      "node-group"    = "cpu-pool"
    }
    gpu-pool = {
      "workload-type" = "gpu"
      "node-group"    = "gpu-pool"
    }
  }

  # Node pool taints (for GPU isolation)  
  node_pools_taints = {
    all      = []
    cpu-pool = []
    gpu-pool = [
      # {
      #   key    = "nvidia.com/gpu"
      #   value  = "Exists"
      #   effect = "NO_SCHEDULE"
      # }
    ]
  }

  #  cluster_autoscaling = {  
  #   enabled                     = true  
  #   autoscaling_profile         = "BALANCED"  
  #   min_cpu_cores               = 1  
  #   max_cpu_cores               = 100  
  #   min_memory_gb               = 1  
  #   max_memory_gb               = 1000  
  #   gpu_resources = [  
  #     {  
  #       resource_type = "nvidia-tesla-t4"  
  #       minimum       = 0  
  #       maximum       = 10  
  #     }  
  #   ]  
  #   auto_repair                 = true  
  #   auto_upgrade                = true  
  # }  



  # Resource labels (equivalent to tags)  
  cluster_resource_labels = var.tags

  depends_on = [  
    module.vllm_gke_project,  
    google_project_service.existing_project_services,
    module.vpc,  
  #  null_resource.cleanup_blocking_firewall
  ]  
}



########################################
# Kubernetes kubeconfig file
########################################
resource "local_file" "kubeconfig" {
  content = templatefile("${path.module}/config/kubeconfig.tpl", {
    cluster_name     = module.gke.name
    cluster_endpoint = module.gke.endpoint
    cluster_ca       = module.gke.ca_certificate
    region           = var.region
    token           = data.google_client_config.default.access_token 
  })
  filename             = "${path.module}/kubeconfig"
  file_permission      = "0600"
  directory_permission = "0755"
}