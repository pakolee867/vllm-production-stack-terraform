# variables.tf
###############################################################################
# 📦  PROVIDER-LEVEL SETTINGS
################################################################################

# Provider-level settings 

# Flag variable to control project creation  
variable "create_project" {
  description = "Whether to create a new project or use existing provider project"
  type        = bool
  default     = false
}
# $ gcloud config set project PROJECT_ID
variable "project_id" {
  description = "GCP project ID for the GKE cluster"
  type        = string
}

variable "region" {
  description = "GCP region for the cluster"
  type        = string
  default     = "us-central1"
}

variable "regional" {
  type    = bool
  default = false

}

variable "zones" {
  description = "GCP zones for the cluster"
  type        = list(string)
  default     = []
  # default     = ["us-central1-a", "us-central1-b", "us-central1-c"]  
}

variable "gcp_services" {
  description = "List of GCP services required for GKE project"
  type        = list(string)
  default = [
    # Core GKE-related services  
    "container.googleapis.com",   # Kubernetes Engine API  
    "compute.googleapis.com",     # Compute Engine API  
    "iam.googleapis.com",         # Identity and Access Management API  
    "monitoring.googleapis.com",  # Cloud Monitoring API  
    "logging.googleapis.com",     # Cloud Logging API  
    "cloudtrace.googleapis.com",  # Cloud Trace API  
    "stackdriver.googleapis.com", # Stackdriver API (legacy, but sometimes needed)  

    # Networking related services  
    "servicenetworking.googleapis.com", # Service Networking API  
    "networkmanagement.googleapis.com", # Network Management API  

    # Storage related services  
    "storage-api.googleapis.com",      # Cloud Storage API  
    "artifactregistry.googleapis.com", # Artifact Registry API  

    # Additional services for cluster-tools.tf  
    "dns.googleapis.com",                # For DNS management  
    "certificatemanager.googleapis.com", # For managed certificates  

    # Binary authorization (if using safer-cluster)  
    "containeranalysis.googleapis.com",   # Container Analysis API  
    "binaryauthorization.googleapis.com", # Binary Authorization API  
    "cloudkms.googleapis.com"             # Cloud KMS API  
  ]
}

################################################################################
# 🍿  GLOBAL TAGS & METADATA
################################################################################

variable "tags" {
  description = "Tags applied to all Azure resources."
  type        = map(string)
  default = {
    project     = "vllm-production-stack"
    environment = "production"
    team        = "llmops"
    application = "ai-inference"
    costcenter  = "ai-1234"
  }
}

################################################################################
# 🌐  NETWORKING – VNET & SUBNETS
################################################################################

variable "create_vpc" {
  description = "Create a new VPC (true) or reuse an existing one (false)."
  type        = bool
  default     = true
}


variable "vpc_id" {
  description = "Existing VPC ID (required when create_vpc = false)."
  type        = string
  default     = ""
}

# VPC parameters (adapted for GCP)  
variable "vpc_name" {
  description = "Name for the VPC network."
  type        = string
  default     = "vllm-vpc"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC (informational - GCP auto-assigns)."
  type        = string
  default     = "10.20.0.0/16"
}

# Subnetwork configuration (GCP uses single subnet + secondary ranges)  
variable "subnetwork_name" {
  description = "Name of the subnetwork for GKE cluster"
  type        = string
  default     = "vllm-subnet"
}

variable "subnetwork_cidr" {
  description = "Primary CIDR for the subnetwork"
  type        = string
  default     = "10.20.1.0/24"
}

# Secondary IP ranges for GKE (replaces pod_cidr/service_cidr)  
variable "pod_range_name" {
  description = "Name of secondary IP range for pods"
  type        = string
  default     = "pods-range"
}

# Overlay pod network 
variable "pod_cidr" {
  type    = string
  default = "10.244.0.0/16"
}

# Overlay service network 
variable "service_range_name" {
  description = "Name of secondary IP range for services"
  type        = string
  default     = "services-range"
}

variable "service_cidr" {
  description = "CIDR block for service IPs"
  type        = string
  default     = "10.96.0.0/16"
}


# Master network configuration (GCP-specific)  
variable "master_ipv4_cidr_block" {
  description = "CIDR block for GKE master network"
  type        = string
  default     = "172.16.0.0/28"
}


# Private cluster settings  
variable "enable_private_endpoint" {
  description = "Enable private endpoint for master access"
  type        = bool
  default     = false
}

variable "enable_private_nodes" {
  description = "Enable private nodes (nodes have internal IPs only)"
  type        = bool
  default     = true
}

variable "network_project_id" {
  description = "The project ID of the shared VPC's host (for shared vpc support)"
  type        = string
  default     = ""
}
################################################################################
# ⚘️  GKE CLUSTER – CORE SETTINGS
################################################################################

variable "cluster_name" {
  description = "GKE cluster name."
  type        = string
  default     = "vllm-gke"
}

variable "cluster_version" {
  description = "Kubernetes version."
  type        = string
  default     = "1.30"
}

# API endpoint exposure
variable "api_public_access" {
  type    = bool
  default = true
}

variable "api_private_access" {
  type    = bool
  default = true
}


variable "managed_identities" {
  description = "Managed identities for AKS."
  type        = list(string)
  default     = []
}


variable "enable_keda" {
  description = "Enable KEDA for workload autoscaling."
  type        = bool
  default     = false
}

variable "enable_vpa" {
  description = "Enable Vertical Pod Autoscaler (VPA)."
  type        = bool
  default     = false
}

variable "image_cleaner_enabled" {
  description = "Enable image cleaner to remove unused images."
  type        = bool
  default     = true
}

variable "image_cleaner_interval_hours" {
  description = "Interval in hours for the image cleaner to run."
  type        = number
  default     = 24

}
variable "run_command_enabled" {
  description = "Enable run command for executing commands on nodes."
  type        = bool
  default     = true
}


################################################################################
# ⚙️  NODE‑GROUP STRATEGY
################################################################################

variable "inference_hardware" {
  description = <<EOT
Choose the hardware profile for inference workloads.
• "cpu" → only the default CPU node‑group
• "gpu" → CPU node‑group + a GPU node‑group (g4dn.xlarge, 1 node)
EOT
  type        = string
  default     = "cpu"
  validation {
    condition     = contains(["cpu", "gpu"], lower(var.inference_hardware))
    error_message = "Valid values are \"cpu\" or \"gpu\"."
  }
}

variable "gpu_node_min_size" {
  type    = number
  default = 1
}

variable "gpu_node_max_size" {
  type    = number
  default = 1
}

variable "cpu_node_min_size" {
  type    = number
  default = 1
}

variable "cpu_node_max_size" {
  type    = number
  default = 2
}
variable "os_image_type" {
  type        = string
  default     = "COS_CONTAINERD"           # Container-Optimized OS  
  description = "Image type for CPU nodes" # "COS_CONTAINERD", "UBUNTU_CONTAINERD", "COS"
}

# OS Disk Type variables  
variable "cpu_disk_type" {
  type        = string
  default     = "pd-standard" # GCP equivalent of "Managed"  
  description = "Disk type for CPU nodes (pd-standard, pd-ssd, pd-balanced)"
}

variable "gpu_disk_type" {
  type        = string
  default     = "pd-ssd" # Better performance for GPU workloads  
  description = "Disk type for GPU nodes (pd-standard, pd-ssd, pd-balanced)"
}

variable "cpu_os_disk_size_gb" {
  type        = number
  default     = 50
  description = "OS disk size for CPU nodes"
}
variable "gpu_os_disk_size_gb" {
  type        = number
  default     = 100
  description = "OS disk size for GPU nodes"
}

################################################################################
# 🤖  GPU OPERATOR ADDON
################################################################################

variable "gpu_operator_file" {
  description = "Path to GPU Operator Helm values YAML."
  type        = string
  default     = "modules/llm-stack/helm/gpu/gpu-operator-values.yaml"
}
################################################################################
# 🔐  TLS / CERT‑MANAGER & LET’S ENCRYPT
################################################################################

variable "enable_cert_manager" {
  type    = bool
  default = true
}

variable "enable_cert_manager_cluster_issuer" {
  type    = bool
  default = true
}

variable "letsencrypt_email" {
  type    = string
  default = "admin@example.com"
}

################################################################################
# 📊  OBSERVABILITY – GRAFANA / PROMETHEUS / METRICS
################################################################################

variable "enable_grafana" {
  type    = bool
  default = true
}

variable "enable_prometheus" {
  type    = bool
  default = true
}

variable "enable_metrics_server" {
  type    = bool
  default = true
}

variable "grafana_admin_password" {
  description = "Grafana admin password."
  type        = string
  default     = "admin1234"
  sensitive   = true
}
################################################################################
# 🔑  SECRETS MANAGEMENT
################################################################################

variable "enable_external_secrets" {
  type    = bool
  default = true
}

################################################################################
# 💾  STORAGE CSI DRIVERS
################################################################################

variable "enable_disk_csi_driver" {
  type    = bool
  default = true
}

variable "enable_file_csi_driver" {
  type    = bool
  default = false
}

variable "enable_file_storage" {
  description = "Enable azure file storage resources for debugging"
  type        = bool
  default     = false
}



################################################################################
# 🎛️  NVIDIA setup selector
################################################################################
/*
 Unlike some Kubernetes distributions where you need to manually install GPU operators
  or device plugins via Helm charts, GKE handles this entire process automatically 
  when you configure GPU node pools
 */

################################################################################
# 🛠️  ADDITIONAL  ADDON SETTINGS
################################################################################


################################################################################
# 🧠 VLLM PRODUCTION STACK SETTINGS
################################################################################
variable "enable_vllm" {
  description = "Enable VLLM production stack add-on"
  type        = bool
  default     = false
}

variable "hf_token" {
  description = "Hugging Face access token with model-download scope"
  type        = string
  sensitive   = true
}

variable "cpu_vllm_helm_config" {
  description = "Path to the Helm chart values template for CPU inference."
  type        = string
  default     = "modules/llm-stack/helm/cpu/cpu-tinyllama-light-ingress-gcp.tpl"
}

variable "gpu_vllm_helm_config" {
  description = "Path to the Helm chart values template for GPU inference."
  type        = string
  default     = "modules/llm-stack/helm/gpu/gpu-tinyllama-light-ingress-gcp.tpl"
}