output "name" {
  description = "Name prefix for the resources."
  value       = var.name
}

output "public_ip" {
  description = "Public IP address of the EC2 instance."
  value       = aws_instance.devcontainers_instance.public_ip
}

output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.devcontainers_instance.id
}

output "devcontainers" {
  description = "List of configured devcontainers with their details."
  value = [
    for c in local.prepared_devcontainers : {
      id     = c.id
      source = c.source.url
      remote_access = merge(
        {},
        c.remote_access.openvscode_server != null ? {
          openvscode_server = {
            url = (local.create_dns_records
              ? "https://${c.id}.${local.subdomain_fqdn}/?tkn={token}"
            : "https://${aws_instance.devcontainers_instance.public_ip}:${c.remote_access.openvscode_server.port}/?tkn={token}"),
            token_ssm_parameter = aws_ssm_parameter.openvscode_tokens[c.id].name
          }
        } : {},
        c.remote_access.ssh != null ? {
          ssh = {
            command = (local.create_dns_records
              ? "ssh -p ${c.remote_access.ssh.port} root@${var.name}.${var.dns.high_level_domain}"
            : "ssh -p ${c.remote_access.ssh.port} root@${aws_instance.devcontainers_instance.public_ip}")
          }
        } : {}
      )
    }
  ]
}
