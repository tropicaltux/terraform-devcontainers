resource "random_uuid" "auto" {
  count = var.devcontainer_id == "" ? 1 : 0
}

locals {
  dev_id     = var.devcontainer_id != "" ? var.devcontainer_id : random_uuid.auto[0].result
  tmp_dir    = "/home/ec2-user/tmp/project-x"
  dns_name   = "ec2-${replace(aws_instance.this.public_ip, ".", "-")}.eu-central-1.compute.amazonaws.com"
  vscode_url = "http://${local.dns_name}:8000"
}

/* ---------- Security Group ---------- */
resource "aws_security_group" "this" {
  name        = "devcontainer-${local.dev_id}"
  description = "Ingress for SSH and VS Code server"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "VS Code / NGINX HTTP"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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
  key_name   = "devcontainer-${local.dev_id}"
  public_key = file(var.public_key_path)
}

/* ---------- EC2 Instance ---------- */
resource "aws_instance" "this" {
  ami                    = "ami-0858a01583863845d"
  instance_type          = var.instance_type
  key_name               = aws_key_pair.this.key_name
  vpc_security_group_ids = [aws_security_group.this.id]

  # Connection block inherited by all provisioners
  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file(chomp(replace(var.public_key_path, ".pub", "")))
    host        = self.public_ip
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

  # 3. Run the deployment script
  provisioner "remote-exec" {
    inline = [
      "export SCRIPTS=${local.tmp_dir}/scripts",
      "export DEVCONTAINER_ID=${local.dev_id}",
      "export REPO_URL=${var.repo_url}",
      "chmod +x $SCRIPTS/devcontainer_up_with_web_ui.sh",
      "$SCRIPTS/devcontainer_up_with_web_ui.sh"
    ]
  }
}
