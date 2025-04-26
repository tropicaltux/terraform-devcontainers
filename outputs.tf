output "name" {
  description = "Name prefix for the resources."
  value       = var.name
}

output "instance_id" {
  description = "ID of the EC2 instance."
  value       = aws_instance.this.id
}

output "dns_name" {
  description = "Public DNS name of the EC2 instance."
  value       = local.dns_name
}

output "devcontainers" {
  description = "List of configured devcontainers with their details."
  value = [
    for idx, container in local.prepared_devcontainers : {
      id     = container.id
      source = container.source
      url    = "http://${aws_instance.this.public_ip}:${container.port}"
      port   = container.port
    }
  ]
}
