##############################
#  Network
##############################
# 1. The module automatically assigns Network Contributor permissions to the cluster identity main.tf:43-47 , 
# allowing AKS to manage necessary network resources dynamically.
##############################
# Control Plane to Node Communication:
#  2. Azure manages the control plane networking automatically. master-to-Node connection happens through Azure's 
#  managed infrastructure and doesn't require custom NSG rules.
#############################
#  3. Pod-to-Pod Traffic Control(No NSG rules) uses Cilium network policy by default for micro-segmentation at the K8s level
#  rather than traditional network policies.
# Note: Node-to-node communication is handled by the Azure CNI plugin.
# The AKS cluster uses Azure CNI with overlay mode:
# Pod-to-pod communication works across subnets in the same vnet. Network policies at pod level, not subnet level.
# Service discovery and load balancing function normally.
##############################
module "vnet" {
  source   = "./modules/az-networking/vnet"
  for_each = var.create_vnet ? { "vnet" = {} } : {}

  # Required parameters for terraform-azurerm-avm-res-network-virtualnetwork  
  location            = var.location
  name                = "${var.prefix}-vnet"
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = [var.vnet_cidr] # ["10.20.0.0/16"]  

  # Subnets configuration  
  subnets = {
    system = {
      name              = "system-subnet"
      address_prefixes  = [var.system_subnet] # ["10.20.1.0/24"]  
      service_endpoints = ["Microsoft.ContainerRegistry"]
    }
    gpu = {
      name              = "gpu-subnet"
      address_prefixes  = [var.gpu_subnet] # ["10.20.2.0/24"]  
      service_endpoints = ["Microsoft.ContainerRegistry"]
    }
    appgw = {
      name             = "appgw-subnet"
      address_prefixes = [var.appgw_subnet] # ["10.20.50.0/24"]  
    }
  }

  # Optional parameters  
  tags = var.tags
}

###########################################
# Use existing VNet if create_vnet is false
###########################################

# Data source for existing VNet  
data "azurerm_virtual_network" "existing" {
  count               = var.create_vnet ? 0 : 1
  name                = split("/", var.vnet_id)[8]
  resource_group_name = split("/", var.vnet_id)[4]
}

############################################################################  
# Alternative: Name-based filtering (commented out by default)  
# Uncomment and modify these if you prefer name-based subnet identification  
############################################################################  
data "azurerm_subnet" "existing_system" {
  count                = var.create_vnet ? 0 : 1
  name                 = "system-subnet" # Adjust to match your actual system subnet name
  resource_group_name  = split("/", var.vnet_id)[4]
  virtual_network_name = data.azurerm_virtual_network.existing[0].name
  # filter {  
  #   name   = "name"  
  #   values = ["*system*", "*aks*", "*node*"]  # Adjust patterns as needed  
  # }  
}

data "azurerm_subnet" "existing_gpu" {
  count                = var.create_vnet ? 0 : 1
  name                 = "gpu-subnet" # Adjust to match your actual GPU subnet name 
  resource_group_name  = split("/", var.vnet_id)[4]
  virtual_network_name = data.azurerm_virtual_network.existing[0].name
  # filter {  
  #   name   = "name"  
  #   values = ["*gpu*"]  # Adjust pattern as needed  
  # }  
}

data "azurerm_subnet" "existing_appgw" {
  count                = var.create_vnet ? 0 : 1
  name                 = "appgw-subnet" # Adjust to match your actual AppGW subnet name  
  resource_group_name  = split("/", var.vnet_id)[4]
  virtual_network_name = data.azurerm_virtual_network.existing[0].name
  # filter {  
  #   name   = "name"  
  #   values = ["*appgw*", "*gateway*"]  # Adjust patterns as needed  
  # }  
}

locals {
  create_new_vnet = var.create_vnet
  # Name-based subnet assignment (commented out)  
  system_subnet_id = (local.create_new_vnet ?
    module.vnet["vnet"].subnets["system"].resource_id :
  data.azurerm_subnet.existing_system[0].id)

  gpu_subnet_id = (local.create_new_vnet ?
    module.vnet["vnet"].subnets["gpu"].resource_id :
  data.azurerm_subnet.existing_gpu[0].id)

  appgw_subnet_id = (local.create_new_vnet ?
    module.vnet["vnet"].subnets["appgw"].resource_id :
  data.azurerm_subnet.existing_appgw[0].id)

  # Network configuration for AKS module  
  network_config = {
    node_subnet_id = local.system_subnet_id
    dns_service_ip = var.dns_service_ip # dns_service_ip must be placed within your service_cidr range
  }
}


####################################################
# INGRESS CONTROLLER
####################################################
# Nginx Ingress Controller with Helm

# Deploy NGINX Ingress Controller  
resource "helm_release" "nginx_ingress" {  
  name       = "ingress-nginx"  
  repository = "https://kubernetes.github.io/ingress-nginx"  
  chart      = "ingress-nginx"  
  namespace  = "ingress-nginx"  
    
  create_namespace = true  
    
values = [    
   <<-EOF
    controller:
      service:
        type: LoadBalancer
        externalTrafficPolicy: Local
        annotations:
          service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path: /healthz
      
      config:
        proxy-body-size: "100m"
        client-max-body-size: "100m"
        proxy-read-timeout: "600"
        proxy-send-timeout: "600"
        proxy-connect-timeout: "60"
      
      metrics:
        enabled: true
      
      podAnnotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "10254"
    EOF 
  ]  
    
  depends_on = [module.aks]  
}  
  
# Get the LoadBalancer IP  
data "kubernetes_service" "nginx_ingress" {  
  metadata {  
    name      = "ingress-nginx-controller"  
    namespace = "ingress-nginx"  
  }  
    
  depends_on = [helm_release.nginx_ingress]  
}  
  
locals {  
  nginx_ip = data.kubernetes_service.nginx_ingress.status.0.load_balancer.0.ingress.0.ip  
  nginx_ip_hex = join("", formatlist("%02x", split(".", data.kubernetes_service.nginx_ingress.status.0.load_balancer.0.ingress.0.ip)))  
}
#####################################################
# Traefik is an alternative ingress controller that can be used with AKS.
# resource "helm_release" "traefik_ingress" {  
#   name       = "traefik"  
#   repository = "https://traefik.github.io/charts"  # Updated repository URL  
#   chart      = "traefik"  
#   namespace  = "traefik-system"  # Standard namespace for Traefik  
#   version    = "25.0.0" 
#   timeout    = 900  
    
#   create_namespace = true  
    
#   values = [  
#     <<EOF  
# service:  
#   type: LoadBalancer  
#   annotations:  
#     service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path: /ping  
  
# ports:  
#   web:  
#     port: 80  
#   websecure:  
#     port: 443  
#     tls:  
#       enabled: true  
# Make Traefik the default ingress class  
# ingressClass:  
#   enabled: true  
#   isDefaultClass: true    

# metrics:  
#   prometheus:  
#     service:  
#       enabled: true  
#     addEntryPointsLabels: true  
#     addServicesLabels: true  
  
# # Enable dashboard for debugging (optional)  
# ingressRoute:  
#   dashboard:  
#     enabled: false  # Set to true if you want the dashboard  
# EOF  
#   ]  
    
#   depends_on = [module.aks]  
# }

##### example grafana traefil Ingress anotaion
# grafana:  
#   ingress:  
#     enabled: true  
#     ingressClassName: traefik  
#     annotations:  
#       cert-manager.io/cluster-issuer: letsencrypt-prod  
#       traefik.ingress.kubernetes.io/router.tls: "true"  
#     hosts:  
#       - grafana.${var.dns_prefix}.nip.io  
#     tls:  
#       - secretName: grafana-tls  
#         hosts:  
#           - grafana.${var.dns_prefix}.nip.io  