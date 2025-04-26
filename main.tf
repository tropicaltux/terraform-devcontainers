locals {
  tmp_dir  = "/home/ec2-user/tmp/project-x"
  dns_name = "ec2-${replace(aws_instance.this.public_ip, ".", "-")}.${data.aws_region.current.name}.compute.amazonaws.com"

  # Set the base start port to 8000
  start_port = 8000

  # Create a map of all devcontainers with UUIDs for IDs and assigned ports
  prepared_devcontainers = [
    for i, c in var.devcontainers : merge(c, {
      id   = c.id != null ? c.id : uuid(),
      port = c.port != null ? c.port : local.start_port + i
    })
  ]

  should_create_key_pair = var.public_ssh_key.local_key_path != null
  key_pair_name          = local.should_create_key_pair ? "${var.name}-key-pair" : var.public_ssh_key.aws_key_pair_name
}

# Get current AWS region
data "aws_region" "current" {}

/* ---------- Security Group ---------- */
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

  # Dynamic ingress rules for all assigned ports
  dynamic "ingress" {
    for_each = local.prepared_devcontainers
    content {
      description = "VS Code / NGINX HTTP for ${ingress.value.id != null ? ingress.value.id : "container-${ingress.key}"}"
      from_port   = ingress.value.port
      to_port     = ingress.value.port
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

/* ---------- Key Pair ---------- */
resource "aws_key_pair" "this" {
  count = local.should_create_key_pair ? 1 : 0

  key_name   = local.key_pair_name
  public_key = local.should_create_key_pair ? file(var.public_ssh_key.local_key_path) : null
}

/* ---------- EC2 Instance ---------- */
resource "aws_instance" "this" {
  ami                    = "ami-0858a01583863845d"
  instance_type          = var.instance_type
  key_name               = local.key_pair_name
  vpc_security_group_ids = [aws_security_group.this.id]

  tags = {
    Name = var.name
  }

  # Connection block inherited by all provisioners
  connection {
    type  = "ssh"
    user  = "ec2-user"
    host  = self.public_ip
    agent = true
  }

  # 1. Prepare a temporary directory
  provisioner "remote-exec" {
    inline = [
      "mkdir -p ${local.tmp_dir}"
    ]
  }

  # 2. Upload your ready‑made scripts
  provisioner "file" {
    source      = "${path.module}/scripts"
    destination = local.tmp_dir
  }

  # 3. Upload devcontainers configuration with ports
  provisioner "file" {
    content     = jsonencode(local.prepared_devcontainers)
    destination = "${local.tmp_dir}/devcontainers.json"
  }

  # 4. Run the Python script to process devcontainers
  provisioner "remote-exec" {
    inline = [
      "chmod +x ${local.tmp_dir}/scripts/devcontainer_up_with_web_ui.sh",
      "python3 ${local.tmp_dir}/scripts/run_devcontainers.py --scripts-dir=${local.tmp_dir}/scripts --config=${local.tmp_dir}/devcontainers.json"
    ]
  }
} 