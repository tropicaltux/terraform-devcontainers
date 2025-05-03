resource "aws_security_group" "this" {
  name        = "${var.name}-security-group"
  description = "Ingress for SSH and VS Code server"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Add OpenVSCode server ports for each devcontainer
  dynamic "ingress" {
    for_each = { for i, c in local.prepared_devcontainers : i => c if try(c.remote_access.openvscode_server, null) != null }
    content {
      description = "OpenVSCode Server for ${ingress.value.id != null ? ingress.value.id : "container-${ingress.key}"}"
      from_port   = ingress.value.remote_access.openvscode_server.port
      to_port     = ingress.value.remote_access.openvscode_server.port
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  # Add SSH ports for each devcontainer
  dynamic "ingress" {
    for_each = { for i, c in local.prepared_devcontainers : i => c if try(c.remote_access.ssh, null) != null }
    content {
      description = "SSH for ${ingress.value.id != null ? ingress.value.id : "container-${ingress.key}"}"
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