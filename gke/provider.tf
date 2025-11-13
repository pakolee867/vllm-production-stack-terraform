# Copyright (c) 2025, Kosseila HD (Cloudthrill), released under MIT License.  

terraform {
  required_version = ">= 1.3, < 2.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.27.0, < 7"
    }
    google-beta = {  
      source  = "hashicorp/google-beta"  
      version = ">= 4.64, < 7"  
    }  
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.10"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.15"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.19.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 2.1"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.5"
    }
  }
}

# Configure the Google provider  
provider "google" {
  project = var.project_id # i.e TF_VAR_project_id  
  region  = var.region
}

provider "google-beta" {  
  project = var.project_id  
  region  = var.region  
}
# Get access token for authentication
data "google_client_config" "default" {}

provider "random" {}

# Kubernetes provider configuration  
provider "kubernetes" {
  host                   = "https://${module.gke.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.ca_certificate)
}

# Helm provider configuration  
provider "helm" {
  kubernetes = {
    host                   = "https://${module.gke.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(module.gke.ca_certificate)
    load_config_file       = false
  }
}

# kubectl provider configuration  
provider "kubectl" {
  host                   = "https://${module.gke.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.ca_certificate)
  load_config_file       = false
}

# Cluster information locals  
locals {
  cluster_endpoint       = module.gke.endpoint
  cluster_ca_certificate = base64decode(module.gke.ca_certificate)
  cluster_id             = module.gke.name
  cluster_region         = var.region
}

##############################################################################
# GCP services activation
##############################################################################
# resource "google_project_service" "services" {  
#     for_each = toset(var.gcp_services)  
#     disable_on_destroy = false  
#     disable_dependent_services = false  
#     project = var.project_id  
#     service = each.value  
# }  

# resource "time_sleep" "wait_60_seconds" {  
#     depends_on = [google_project_service.services]  
#     create_duration = "60s"  
# }