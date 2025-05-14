# Put individual SSH keys for devcontainers that specify their own keys into SSM Parameter Store
resource "aws_ssm_parameter" "container_ssh_public_keys" {
  for_each = {
    for c in local.prepared_devcontainers : c.id => c
    if try(c.remote_access.ssh, null) != null
  }

  name        = "/${var.name}/devcontainers/${each.value.id}/ssh-public-key"
  description = "SSH public key for devcontainer ${each.value.id}"
  type        = "SecureString"
  value       = try(each.value.remote_access.ssh.public_ssh_key.local_key_path, null) != null ? file(each.value.remote_access.ssh.public_ssh_key.local_key_path) : data.aws_key_pair.container_specific[each.key].public_key
}

# Put generated random tokens for each devcontainer into SSM Parameter Store
resource "aws_ssm_parameter" "openvscode_tokens" {
  for_each = {
    for c in local.prepared_devcontainers : c.id => c
    if try(c.remote_access.openvscode_server, null) != null
  }

  name        = "/${var.name}/devcontainers/${each.value.id}/openvscode-token"
  description = "OpenVSCode Server token for devcontainer ${each.value.id}"
  type        = "SecureString"
  value_wo    = ephemeral.random_password.tokens[each.key].result
  value_wo_version = 1
}

# Generate random tokens for each devcontainer
ephemeral "random_password" "tokens" {
  for_each = { for c in local.prepared_devcontainers : c.id => c }

  length  = 32
  special = false
}