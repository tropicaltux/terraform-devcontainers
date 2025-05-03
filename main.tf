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
    if try(c.remote_access.ssh, null) != null
  }

  name        = "/${var.name}/devcontainers/${each.value.id}/ssh-public-key"
  description = "SSH public key for devcontainer ${each.value.id}"
  type        = "SecureString"
  value       = try(each.value.remote_access.ssh.public_ssh_key.local_key_path, null) != null ? file(each.value.remote_access.ssh.public_ssh_key.local_key_path) : data.aws_key_pair.container_specific[each.key].public_key
}

# Get container-specific AWS Key Pairs if aws_key_pair_name is specified
data "aws_key_pair" "container_specific" {
  for_each = {
    for i, c in local.prepared_devcontainers : tostring(i) => c.remote_access.ssh.public_ssh_key.aws_key_pair_name
    if try(c.remote_access.ssh, null) != null &&
    try(c.remote_access.ssh.public_ssh_key.aws_key_pair_name, null) != null
  }

  key_name = each.value
}

/* ---------- OpenVSCode Server Tokens ---------- */
resource "random_password" "tokens" {
  for_each = { for i, c in local.prepared_devcontainers : tostring(i) => c }

  length  = 32
  special = false
}

resource "aws_ssm_parameter" "openvscode_tokens" {
  for_each = {
    for i, c in local.prepared_devcontainers : tostring(i) => c
    if try(c.remote_access.openvscode_server, null) != null
  }

  name        = "/${var.name}/devcontainers/${each.value.id}/openvscode-token"
  description = "OpenVSCode Server token for devcontainer ${each.value.id}"
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
      "chmod +x ${local.tmp_dir}/scripts/clone_repository.sh",

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