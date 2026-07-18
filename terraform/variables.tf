variable "kubeconfig_path" {
  description = "Path to the kubeconfig file."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "kubectl context created by k3d."
  type        = string
  default     = "k3d-devops-demo"
}

variable "git_repo_url" {
  description = "HTTPS URL of the public Git repository monitored by Argo CD."
  type        = string

  validation {
    condition     = startswith(var.git_repo_url, "https://")
    error_message = "git_repo_url must be an HTTPS URL."
  }
}

variable "git_revision" {
  description = "Git branch, tag, or commit used by Argo CD."
  type        = string
  default     = "main"
}

variable "workload_namespace" {
  description = "Namespace for MySQL, backups, frontend, and backend."
  type        = string
  default     = "demo"
}

variable "argocd_chart_version" {
  description = "Pinned version of the Argo CD Helm chart."
  type        = string
  default     = "10.1.4"
}

variable "mysql_root_password" {
  description = "Password for the MySQL root user."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.mysql_root_password) >= 16
    error_message = "mysql_root_password must contain at least 16 characters."
  }
}

variable "mysql_app_password" {
  description = "Password for the MySQL application user."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.mysql_app_password) >= 16
    error_message = "mysql_app_password must contain at least 16 characters."
  }
}
