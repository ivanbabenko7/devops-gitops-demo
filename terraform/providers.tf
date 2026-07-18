locals {
  kubeconfig_path = pathexpand(var.kubeconfig_path)
}

provider "kubernetes" {
  config_path    = local.kubeconfig_path
  config_context = var.kube_context
}

provider "helm" {
  kubernetes = {
    config_path    = local.kubeconfig_path
    config_context = var.kube_context
  }
}

provider "kubectl" {
  config_path       = local.kubeconfig_path
  config_context    = var.kube_context
  load_config_file  = true
  apply_retry_count = 15
}
