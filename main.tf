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

  filter {
    name   = "architecture"
    values = [var.architecture]
  }
}

resource "terraform_data" "instance_dependent_data" {
  input = {
    devcontainers = var.devcontainers
    dns = var.dns
  }
}

resource "aws_instance" "devcontainers_instance" {
  ami                         = data.aws_ami.devcontainers.id
  instance_type               = var.instance_type
  key_name                    = local.key_pair_name
  vpc_security_group_ids      = [aws_security_group.instance_security_group.id]
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
    aws_instance.devcontainers_instance, aws_route53_zone.subdomain, aws_route53_record.subdomain_a,
    aws_route53_record.wildcard, aws_route53_record.subdomain_delegation
  ]

  lifecycle {
    create_before_destroy = true
    replace_triggered_by = [
      aws_instance.devcontainers_instance
    ]
  }

  # Connection block inherited by all provisioners
  connection {
    type  = "ssh"
    user  = "ec2-user"
    host  = aws_instance.devcontainers_instance.public_ip
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

  # 3. Upload devcontainers configuration
  provisioner "file" {
    content     = jsonencode(local.prepared_devcontainers)
    destination = "${local.tmp_dir}/devcontainers.json"
  }

  # 4. Configure nginx and run the Python script to process devcontainers
  provisioner "remote-exec" {
    inline = [
      "chmod +x ${local.tmp_dir}/scripts/configure_and_run_devcontainers.sh",
      "${local.tmp_dir}/scripts/configure_and_run_devcontainers.sh ${local.tmp_dir} ${var.name} ${aws_instance.devcontainers_instance.public_ip} ${local.subdomain_fqdn}"
    ]
  }
}

