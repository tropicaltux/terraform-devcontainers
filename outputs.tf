output "dns_name" {
  description = "Public DNS name of the EC2 instance."
  value       = local.dns_name
}

output "vscode_server_url" {
  description = "URL to access the VS Code server running inside the devcontainer."
  value       = local.vscode_url
}
