locals {
  tmp_dir  = "/home/ec2-user/tmp/terraform-devcontainers"
  dns_name = "ec2-${replace(aws_instance.this.public_ip, ".", "-")}.${data.aws_region.current.name}.compute.amazonaws.com"

  # Set the base start port to 8000
  start_port = 8000

  # Create a map of all devcontainers with UUIDs for IDs and assigned ports
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
              { port = coalesce(c.remote_access.openvscode_server.port, local.start_port + i * 2) }
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
                port           = coalesce(c.remote_access.ssh.port, local.start_port + i * 2 + 1),
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

  # Add OpenVSCode server ports for each devcontainer
  dynamic "ingress" {
    for_each = { for i, c in local.prepared_devcontainers : i => c if c.remote_access.openvscode_server != null }
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
    for_each = { for i, c in local.prepared_devcontainers : i => c if c.remote_access.ssh != null }
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

/* ---------- Key Pair ---------- */
resource "aws_key_pair" "this" {
  count = local.should_create_key_pair ? 1 : 0

  key_name   = local.key_pair_name
  public_key = local.should_create_key_pair ? file(var.public_ssh_key.local_key_path) : null
}

/* ---------- SSH Public Keys in SSM Parameter Store ---------- */
# Individual SSH keys for devcontainers that specify their own keys
resource "aws_ssm_parameter" "container_ssh_public_keys" {
  for_each = {
    for i, c in local.prepared_devcontainers : tostring(i) => c
    if c.remote_access.ssh != null &&
    (try(c.remote_access.ssh.public_ssh_key.local_key_path, null) != null ||
    try(c.remote_access.ssh.public_ssh_key.aws_key_pair_name, null) != null)
  }

  name        = "/${var.name}/devcontainers/${each.value.id}/ssh-public-key"
  description = "SSH public key for devcontainer ${each.value.id}"
  type        = "SecureString"
  value       = each.value.remote_access.ssh.public_ssh_key.local_key_path != null ? file(each.value.remote_access.ssh.public_ssh_key.local_key_path) : data.aws_key_pair.container_specific[each.key].public_key
}

# Get container-specific AWS Key Pairs if aws_key_pair_name is specified
data "aws_key_pair" "container_specific" {
  for_each = {
    for i, c in local.prepared_devcontainers : tostring(i) => c.remote_access.ssh.public_ssh_key.aws_key_pair_name
    if c.remote_access.ssh != null &&
    try(c.remote_access.ssh.public_ssh_key.aws_key_pair_name, null) != null
  }

  key_name = each.value
}

/* ---------- OpenVSCode Server Tokens ---------- */
resource "random_password" "tokens" {
  for_each = { for i, _ in var.devcontainers : tostring(i) => i }

  length  = 32
  special = false
}

resource "aws_ssm_parameter" "openvscode_tokens" {
  for_each = { for i, _ in var.devcontainers : tostring(i) => i }

  name        = "/${var.name}/devcontainers/${local.prepared_devcontainers[each.value].id}/openvscode-token"
  description = "OpenVSCode Server token for devcontainer ${local.prepared_devcontainers[each.value].id}"
  type        = "SecureString"
  value       = random_password.tokens[each.key].result
}

/* ---------- EC2 Instance ---------- */
resource "aws_instance" "this" {
  ami                    = "ami-015fc6180c36c472c"
  instance_type          = var.instance_type
  key_name               = local.key_pair_name
  vpc_security_group_ids = [aws_security_group.this.id]

  tags = {
    Name = var.name
  }

  # IAM instance profile for accessing Secrets Manager
  iam_instance_profile = aws_iam_instance_profile.openvscode_secrets.name

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

  # 4. Configure nginx and run the Python script to process devcontainers
  provisioner "remote-exec" {
    inline = [
      # Make scripts executable
      "chmod +x ${local.tmp_dir}/scripts/generate-self-sing-cert.sh",
      "chmod +x ${local.tmp_dir}/scripts/devcontainer_up_with_web_ui.sh",

      # Create streams nginx directories
      "sudo mkdir -p /etc/nginx/streams",
      
      # Copy nginx configuration files
      "sudo cp ${local.tmp_dir}/scripts/nginx.config /etc/nginx/nginx.conf",
      "sudo cp ${local.tmp_dir}/scripts/ws_params.conf /etc/nginx/conf.d/ws_params.conf",
      
      # Generate SSL certificate for nginx
      "sudo PUBLIC_IP=${self.public_ip} ${local.tmp_dir}/scripts/generate-self-sing-cert.sh",

      # Run devcontainers script
      "python3 ${local.tmp_dir}/scripts/run_devcontainers.py --name-prefix=${var.name} --public-ip=${self.public_ip} --scripts-dir=${local.tmp_dir}/scripts --config=${local.tmp_dir}/devcontainers.json",
      
      # Clean up
      "rm -rf ${local.tmp_dir}"
    ]
  }
}