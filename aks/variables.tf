# variables.tf
###############################################################################
# 📦  PROVIDER-LEVEL SETTINGS
################################################################################

variable "subscription_id" {
  description = "Azure subscription ID for the AKS cluster."
  type        = string
  default     = ""  
  
}

variable "tenant_id" {
  description = "Azure AD tenant ID for the AKS cluster."
  type        = string
  default     = ""
}

variable "client_id" {
  description = "Azure AD client ID for the AKS cluster."
  type        = string
  default     = ""
}

variable "client_secret" {
  description = "Azure AD client secret for the AKS cluster."
  type        = string
  default     = ""
  sensitive   = true
}
variable "location" {
  type    = string
  default = "eastus" # "canadacentral" 
}
variable "prefix" {
  type    = string
  default = "vllm-aks"
}


variable "rbac_aad_azure_rbac_enabled" {
  description = "Enable Azure RBAC for AKS"
  type        = bool
  default     = true
}
variable "rbac_aad_tenant_id" {
  description = "Azure AD tenant ID for AKS RBAC"
  type        = string
  default     = ""
}

################################################################################
# 🍿  GLOBAL TAGS & METADATA
################################################################################

variable "tags" {
  description = "Tags applied to all Azure resources."
  type        = map(string)
  default = {
    Project     = "vllm-production-stack"
    Environment = "production"
    Team        = "LLMOps"
    Application = "ai-inference"
    CostCenter  = "AI-1234"
  }
}

################################################################################
# 🌐  NETWORKING – VNET & SUBNETS
################################################################################

variable "create_vnet" {
  description = "Create a new VNET (true) or reuse an existing one (false)."
  type        = bool
  default     = true
}

variable "vnet_id" {
  description = "Existing VNET ID (required when create_vnet = false)."
  type        = string
  default     = ""
}

# New‑VNET parameters (ignored when create_vnet = false)
variable "vnet_name" {
  description = "Name for the VNET."
  type        = string
  default     = "vllm-vnet" # Default name for new VNET
}

variable "vnet_cidr" {
  description = "CIDR block for the VNET."
  type        = string
  default     = "10.20.0.0/16"
}

variable "system_subnet" {
  type    = string
  default = "10.20.1.0/24"
} # system pool
variable "gpu_subnet" {
  type    = string
  default = "10.20.2.0/24"
} # gpu pool

# Overlay pod network (keep your 10.244.0.0/16)
variable "pod_cidr" {
  type    = string
  default = "10.244.0.0/16"
}

# Service CIDR (ClusterIP/DNS) — non-overlapping
variable "service_cidr" {
  type    = string
  default = "10.96.0.0/16"
}
variable "dns_service_ip" {
  type    = string
  default = "10.96.0.10"
}

# **AGIC requirement with Overlay**: dedicate a /24 for App Gateway
variable "appgw_subnet" {
  type    = string
  default = "10.20.50.0/24"
}


variable "enable_dns_support" {
  type    = bool
  default = true
}

variable "outbound_type" {
  description = "Outbound type for AKS"
  type        = string
  default     = "loadBalancer"
}

# network_plugin = "azure" is hardcoded
# network_plugin_mode = "overlay" is hardcoded
# load_balancer_sku = "standard" is hardcoded
# network_data_plane is conditionally set based on your network_policy variable
# AKS production module will automatically calculate dns_service_ip based on service_cidr| cidrhost(var.network.service_cidr, 10)
################################################################################
# ⚘️  EKS CLUSTER – CORE SETTINGS
################################################################################

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
  default     = "vllm-aks"
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

variable "http_app_routing_enabled" {
  description = "Enable HTTP application routing."
  type        = bool
  default     = false

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

# OS Disk Type variables  
variable "cpu_os_disk_type" {
  type        = string
  default     = "Managed" # "Ephemeral" when VM supports it like Standard_D8s_v4
  description = "OS disk type for CPU nodes"
}

variable "gpu_os_disk_type" {
  type        = string
  default     = "Ephemeral" #""Managed"  
  description = "OS disk type for GPU nodes"
}

# Node Mode variables  
variable "node_mode" {
  type        = string
  default     = "User"
  description = "Node pool mode for CPU nodes"
}

# OS SKU variables  
variable "cpu_os_sku" {
  type        = string
  default     = "AzureLinux"
  description = "OS SKU for CPU nodes"
}

variable "gpu_os_sku" {
  type        = string
  default     = "AzureLinux"
  description = "OS SKU for GPU nodes"
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
# 🔒  NETWORKING ADD‑ONS
################################################################################
variable "network_policy" {
  type        = string
  default     = "cilium"
  description = "(Optional) Sets up network policy to be used with Azure CNI. Network policy allows us to control the traffic flow between pods. Currently supported values are calico and cilium. Defaults to cilium."
  nullable    = false

  validation {
    condition     = can(regex("^(calico|cilium)$", var.network_policy))
    error_message = "network_policy must be either calico or cilium."
  }
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
  default     = "modules/llm-stack/helm/cpu/cpu-tinyllama-light-ingress-azure.tpl"
}

variable "gpu_vllm_helm_config" {
  description = "Path to the Helm chart values template for GPU inference."
  type        = string
  default     = "modules/llm-stack/helm/gpu/gpu-tinyllama-light-ingress-azure.tpl"
}