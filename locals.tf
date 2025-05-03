# Get current AWS region
data "aws_region" "current" {}

locals {
  tmp_dir  = "/home/ec2-user/tmp/terraform-devcontainers"
  dns_name = "ec2-${replace(aws_instance.this.public_ip, ".", "-")}.${data.aws_region.current.name}.compute.amazonaws.com"

  # Starting bases for automatic port allocation
  start_openvscode_server_port = 8000
  start_ssh_port               = 2222

  # Collect ports explicitly set by the user so we do not reuse them
  user_defined_ports = distinct(flatten([
    for dc in var.devcontainers : concat(
      try(dc.remote_access.openvscode_server.port, null) != null ? [dc.remote_access.openvscode_server.port] : [],
      try(dc.remote_access.ssh.port, null) != null ? [dc.remote_access.ssh.port] : []
    )
  ]))

  # Pre-allocate conflict-free ports for every devcontainer index
  openvscode_auto_ports = zipmap(
    [for idx in range(length(var.devcontainers)) : idx],
    slice([
      for p in range(local.start_openvscode_server_port, local.start_openvscode_server_port + 1024) :
      p if !contains(local.user_defined_ports, p)
    ], 0, length(var.devcontainers))
  )

  ssh_auto_ports = zipmap(
    [for idx in range(length(var.devcontainers)) : idx],
    slice([
      for p in range(local.start_ssh_port, local.start_ssh_port + 1024) :
      p if !contains(local.user_defined_ports, p)
    ], 0, length(var.devcontainers))
  )

  # Post-process devcontainers to assign unique IDs and ports
  prepared_devcontainers = [
    for i, c in var.devcontainers : merge(c, {
      # Generate a unique ID for each devcontainer if not provided
      id = c.id != null ? c.id : uuid(),

      # Configure remote access for each devcontainer
      remote_access = merge(
        # Preserve original remote_access configuration
        c.remote_access,
        {
          # Configure OpenVSCode server access
          openvscode_server = (
            # If OpenVSCode server is explicitly configured
            try(c.remote_access.openvscode_server, null) != null ? merge(
              c.remote_access.openvscode_server,
              { port = coalesce(c.remote_access.openvscode_server.port, local.openvscode_auto_ports[i]) }
            ) :
            # Otherwise, don't configure OpenVSCode server
            null
          ),

          # Configure SSH access
          ssh = (
            # If SSH is explicitly configured
            try(c.remote_access.ssh, null) != null ? merge(
              c.remote_access.ssh,
              {
                port           = coalesce(c.remote_access.ssh.port, local.ssh_auto_ports[i]),
                public_ssh_key = coalesce(c.remote_access.ssh.public_ssh_key, var.public_ssh_key)
              }
            ) :
            # Otherwise, don't configure SSH
            null
          )
        }
      )
    })
  ]


  should_create_key_pair = var.public_ssh_key.local_key_path != null
  key_pair_name          = local.should_create_key_pair ? "${var.name}-key-pair" : var.public_ssh_key.aws_key_pair_name
}