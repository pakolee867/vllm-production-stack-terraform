terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0.0, < 5.0.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0, < 4.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.15.1"
      # https://registry.terraform.io/providers/hashicorp/helm/
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.22.0"
    }

    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.19.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.5"
      # https://registry.terraform.io/providers/hashicorp/local/
    }
  }
}

provider "azurerm" {
  features {}
  resource_provider_registrations = "none"
  subscription_id = var.subscription_id  
#   tenant_id       = var.tenant_id  
#   client_id       = var.client_id  
#   client_secret   = var.client_secret  
}

provider "azapi" {}

provider "random" {}

provider "helm" {  
  kubernetes ={  
    host                   = module.aks.host  
    cluster_ca_certificate = base64decode(module.aks.cluster_ca_certificate[0].cluster_ca_certificate)  
    client_certificate     = base64decode(module.aks.kube_admin_config[0].client_certificate)  
    client_key             = base64decode(module.aks.kube_admin_config[0].client_key)  
  }  
}
# provider "helm" {  
#   kubernetes = {  
#     host                   = module.aks.host    
#     cluster_ca_certificate = base64decode(module.aks.cluster_ca_certificate[0].cluster_ca_certificate)    
#     exec = {  # Add equals sign here  
#       api_version = "client.authentication.k8s.io/v1"    
#       command     = "az"    
#       args = [    
#         "aks",    
#         "get-credentials",    
#         "--resource-group", "vllm-aks-rg",    
#         "--name", "vllm-aks",    
#         "--admin", 
#         "--format", "exec"    
#       ]    
#     }   
#   }  
# }


provider "kubectl" {
  config_path = local_file.kubeconfig.filename
}

# provider "kubernetes" {
#   host                   = module.aks.host
#   cluster_ca_certificate = base64decode(module.aks.cluster_ca_certificate[0].cluster_ca_certificate)
#   client_certificate     = base64decode(module.aks.kube_config[0].client_certificate)  
#   client_key             = base64decode(module.aks.kube_config[0].client_key)  
# }

provider "kubernetes" {  
  host                   = module.aks.host  
  cluster_ca_certificate = base64decode(module.aks.cluster_ca_certificate[0].cluster_ca_certificate)  
  client_certificate     = base64decode(module.aks.kube_admin_config[0].client_certificate)  
  client_key             = base64decode(module.aks.kube_admin_config[0].client_key)  
}
# provider "kubernetes" {  
#   host                   = module.aks.host  
#   cluster_ca_certificate = base64decode(module.aks.cluster_ca_certificate[0].cluster_ca_certificate)  
#   exec {  
#     api_version = "client.authentication.k8s.io/v1"  
#     command     = "az"  
#     args = [  
#       "aks",  
#       "get-credentials",  
#       "--resource-group", "vllm-aks-rg",  
#       "--name", "vllm-aks", 
#        "--admin",   
#       "--format", "exec"  
#     ]  
#   }  
# }