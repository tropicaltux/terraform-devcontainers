resource "aws_key_pair" "this" {
  count = local.should_create_key_pair ? 1 : 0

  key_name   = local.key_pair_name
  public_key = local.should_create_key_pair ? file(var.public_ssh_key.local_key_path) : null
}

# Get container-specific AWS Key Pairs if aws_key_pair_name is specified
data "aws_key_pair" "container_specific" {
  for_each = {
    for c in local.prepared_devcontainers : c.id => c.remote_access.ssh.public_ssh_key.aws_key_pair_name
    if try(c.remote_access.ssh, null) != null &&
    try(c.remote_access.ssh.public_ssh_key.aws_key_pair_name, null) != null
  }

  key_name = each.value
}