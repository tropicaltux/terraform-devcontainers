resource "aws_security_group" "instance_security_group" {
  name        = "${var.name}-security-group"
  description = "Ingress for SSH and VS Code server"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = local.create_dns_records ? [1] : []

    content {
      description = "HTTP OpenVSCode Server with DNS"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  dynamic "ingress" {
    for_each = local.create_dns_records ? [1] : []

    content {
      description = "HTTPS OpenVSCode Server with DNS"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  # Add OpenVSCode server ports for each devcontainer
  dynamic "ingress" {
    for_each = {
      for c in local.prepared_devcontainers : c.id => c
      if !local.create_dns_records && try(c.remote_access.openvscode_server, null) != null
    }
    content {
      description = "OpenVSCode Server for ${coalesce(ingress.value.id, "container-${ingress.key}")}"
      from_port   = ingress.value.remote_access.openvscode_server.port
      to_port     = ingress.value.remote_access.openvscode_server.port
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  # Add SSH ports for each devcontainer
  dynamic "ingress" {
    for_each = { for c in local.prepared_devcontainers : c.id => c if try(c.remote_access.ssh, null) != null }
    content {
      description = "SSH for ${coalesce(ingress.value.id, "container-${ingress.key}")}"
      from_port   = ingress.value.remote_access.ssh.port
      to_port     = ingress.value.remote_access.ssh.port
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}