data "aws_ami" "devcontainers" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["amazon-linux-2023-devcontainers-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "terraform_data" "instance_dependent_data" {
  input = {
    devcontainers = var.devcontainers
    dns = var.dns
  }
}

resource "aws_instance" "this" {
  ami                         = data.aws_ami.devcontainers.id
  instance_type               = var.instance_type
  key_name                    = local.key_pair_name
  vpc_security_group_ids      = [aws_security_group.this.id]
  associate_public_ip_address = true

  tags = {
    Name = var.name
  }

  lifecycle {
    create_before_destroy = true
    replace_triggered_by = [
      terraform_data.instance_dependent_data
    ]
  }

  # IAM instance profile for accessing Secrets Manager
  iam_instance_profile = aws_iam_instance_profile.devcontainers_instance_profile.name
}

resource "null_resource" "run_devcontainers" {
  depends_on = [
    aws_instance.this, aws_route53_zone.subdomain, aws_route53_record.subdomain_a,
    aws_route53_record.wildcard, aws_route53_record.subdomain_delegation
  ]

  lifecycle {
    create_before_destroy = true
    replace_triggered_by = [
      aws_instance.this
    ]
  }

  # Connection block inherited by all provisioners
  connection {
    type  = "ssh"
    user  = "ec2-user"
    host  = aws_instance.this.public_ip
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
      "chmod +x ${local.tmp_dir}/scripts/dns-propagation-check.sh",

      # Create streams nginx directories
      "sudo mkdir -p /etc/nginx/streams",

      # Create letsencrypt directory
      "sudo mkdir -p /var/www/letsencrypt",

      # Copy nginx configuration files
      "sudo cp ${local.tmp_dir}/scripts/nginx.config /etc/nginx/nginx.conf",
      "sudo cp ${local.tmp_dir}/scripts/ws_params.conf /etc/nginx/conf.d/ws_params.conf",

      # Generate self-signed SSL certificate for nginx only if not using DNS
      "if [ \"${local.create_dns_records}\" != \"true\" ]; then sudo PUBLIC_IP=${aws_instance.this.public_ip} ${local.tmp_dir}/scripts/generate-self-sing-cert.sh; fi",

      # Run devcontainers script
      "python3 ${local.tmp_dir}/scripts/run_devcontainers.py --name-prefix=${var.name} --public-ip=${aws_instance.this.public_ip} --scripts-dir=${local.tmp_dir}/scripts --config=${local.tmp_dir}/devcontainers.json${local.create_dns_records ? " --high-level-domain=${local.subdomain_fqdn}" : ""}",

      # Clean up
      "rm -rf ${local.tmp_dir}"
    ]
  }
}

