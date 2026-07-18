output "frontend_url" {
  description = "Frontend URL exposed by k3d through Traefik."
  value       = "http://localhost:8080"
}

output "argocd_url" {
  description = "Argo CD URL after starting the local port-forward."
  value       = "http://localhost:8081"
}

output "argocd_port_forward_command" {
  description = "Run this command and leave it open to access the Argo CD UI."
  value       = "kubectl -n argocd port-forward svc/argocd-server 8081:80"
}

output "argocd_initial_password_command" {
  description = "Print the initial Argo CD admin password."
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo"
}

output "workload_namespace" {
  description = "Namespace containing MySQL, backup, frontend, and backend resources."
  value       = kubernetes_namespace_v1.workloads.metadata[0].name
}
