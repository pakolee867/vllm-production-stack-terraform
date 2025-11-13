##############################
#  Network
##############################
# 1. Module auto-creates service account with minimal permissions (logging, monitoring, registry access)  
##############################  
# Control Plane to Node Communication:  
# 2. Google manages control plane networking via private backbone.   
# master_ipv4_cidr_block handles secure master-to-node communication.  
#############################  
# 3. Pod-to-Pod Traffic Control: Uses Dataplane V2 (ADVANCED_DATAPATH) with eBPF   
# for micro-segmentation instead of separate Calico addon.  
# Note: Single subnet + secondary IP ranges (ip_range_pods/ip_range_services)   
# replace other cloud providers multi-subnet approach. Network policies at pod level, not subnet level.  
# Service discovery and load balancing work through GKE's built-in capabilities.
# 4. Network Project Logic
# # VPC Module (new resources):  
#   - Always uses local.target_project_id regardless of network_project_id  
#   - Keeps all new resources in the same project (no shared VPC complexity)  
#  
# Data Sources (existing resources):  
#   if Create VPC = false, Create Project = false, network_project_id not null => var.network_project_id  
#   if Create VPC = false, Create Project = false, network_project_id null => local.target_project_id    
#   if Create VPC = false, Create Project = true, network_project_id any => local.target_project_id  
#   (Create VPC = true scenarios don't use data sources)  
######################
#   Zones 
######################
# Conditional zone discovery - only for zonal clusters  
data "google_compute_zones" "zonal_available" {  
  count   = var.regional ? 0 : 1  # Only run when regional = false  
  project = local.target_project_id  
  region  = var.region  
}  

locals {  
  # For zonal clusters: use first available zone, for regional: use empty list  
  selected_zones = var.regional ? var.zones : [data.google_compute_zones.zonal_available[0].names[1]]  # or [0] for first zone
  # GPU nodes: use zones with T4 availability (us-east1-c or us-east1-d)
  gpu_zones = var.regional ? var.zones : [data.google_compute_zones.zonal_available[0].names[1]]  # us-east1-c
}  
 

################################################################################  
# VPC MODULE - Create or use existing VPC  
################################################################################  
module "vpc" {
  source = "./modules/google-network"
  # version  = "~> 9.0"  
  for_each = var.create_vpc ? { "vpc" = {} } : {}

  # Required parameters  
  project_id   = local.target_project_id
  network_name = var.vpc_name
  routing_mode = "REGIONAL"

  # Subnets configuration (GCP uses single subnet + secondary ranges)  
  subnets = [
    {
      subnet_name           = var.subnetwork_name
      subnet_ip             = var.subnetwork_cidr
      subnet_region         = var.region
      subnet_private_access = "true"
      subnet_flow_logs      = "true"
      description           = "GKE cluster subnet"
    }
  ]

  # Secondary IP ranges for GKE pods and services (singular naming)  
  secondary_ranges = {
    (var.subnetwork_name) = [
      {
        range_name    = var.pod_range_name
        ip_cidr_range = var.pod_cidr
      },
      {
        range_name    = var.service_range_name
        ip_cidr_range = var.service_cidr
      }
    ]
  }

  # Optional parameters  
  delete_default_internet_gateway_routes = false

    depends_on = [  
    module.vllm_gke_project,  
    google_project_service.existing_project_services , 
  ]  
}

################################################################################  
# Use existing VPC if create_vpc is false  
################################################################################  

# Data source for existing VPC  
data "google_compute_network" "existing" {
  count   = var.create_vpc ? 0 : 1
  name    = var.vpc_name
  project = (!var.create_project && var.network_project_id != "") ? var.network_project_id : local.target_project_id
}

# Data source for existing subnet  
data "google_compute_subnetwork" "existing" {
  count   = var.create_vpc ? 0 : 1
  name    = var.subnetwork_name
  region  = var.region
  project = (!var.create_project && var.network_project_id != "") ? var.network_project_id : local.target_project_id
}

################################################################################  
# Local values for network configuration  
################################################################################  

locals {
  create_new_vpc = var.create_vpc

  # Network references  
  vpc_name    = local.create_new_vpc ? module.vpc["vpc"].network_name : data.google_compute_network.existing[0].name
  subnet_name = local.create_new_vpc ? module.vpc["vpc"].subnets_names[0] : data.google_compute_subnetwork.existing[0].name

  # Network configuration for GKE module (singular naming)  
  network_config = {
    network    = local.vpc_name
    subnetwork = local.subnet_name
  }
}

####################################################
# NAT GATEWAY Configuration
####################################################
resource "google_compute_router" "router" {  
  count   = var.create_vpc ? 1 : 0  
  name    = "${var.vpc_name}-router"  
  region  = var.region  
  network = local.network_config.network  # Ensure this resolves to network name  
  project = local.target_project_id  
}  
  
resource "google_compute_router_nat" "nat" {  
  count   = var.create_vpc ? 1 : 0  
  name    = "${var.vpc_name}-nat"  
  router  = google_compute_router.router[0].name  
  region  = var.region  
  project = local.target_project_id  
    
  nat_ip_allocate_option             = "AUTO_ONLY"  
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"  
    
  log_config {  
    enable = true  
    filter = "ERRORS_ONLY"  
  }  
}

####################################################
# INGRESS CONTROLLER
####################################################
# Reserved IP for GKE native Ingress Controller  
resource "google_compute_global_address" "ingress_ip" {
  name         = "ingress-ip"
  project      = local.target_project_id
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
}

# Reserved IP for GKE native Ingress Controller  
resource "google_compute_global_address" "vllm_ip" {
  name         = "vllm-ip"
  project      = local.target_project_id
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
}


locals {
  # Fix variable name to match your template
  ingress_ip_hex = join("", formatlist("%02x", split(".", google_compute_global_address.ingress_ip.address)))
  vllm_ip_hex    = join("", formatlist("%02x", split(".", google_compute_global_address.vllm_ip.address)))
}

# locals {
#   nginx_ip     = data.kubernetes_service.nginx_ingress.status.0.load_balancer.0.ingress.0.ip
#   nginx_ip_hex = join("", formatlist("%02x", split(".", data.kubernetes_service.nginx_ingress.status.0.load_balancer.0.ingress.0.ip)))
# }
 