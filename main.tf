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