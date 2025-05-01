packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.8"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "architecture" {
  type    = string
  default = "x86_64"
}

source "amazon-ebs" "amazon_linux_2023" {
  region                      = var.region
  instance_type               = "t2.micro"
  ami_name                    = "amazon-linux-2023-devcontainers-${var.architecture}-{{timestamp}}"
  ssh_username                = "ec2-user"
  associate_public_ip_address = true

  source_ami_filter {
    filters = {
      name                = "al2023-ami-2023*-kernel-6.1-${var.architecture}"
      virtualization-type = "hvm"
      root-device-type    = "ebs"
    }
    most_recent = true
    owners      = ["137112412989"]
  }

  tags = {
    "Name" = "Amazon Linux 2023 Dev Containers (${var.architecture})"
    # "Project"     = "Project-X"
    "Owner"       = "tropicaltux@proton.me"
    "CreatedBy"   = "Packer"
    "Application" = "Dev Container"
    "Version"     = "0.1.0"
  }
}

build {
  name    = "amazon-linux-2023-devcontainers-${var.architecture}"
  sources = ["source.amazon-ebs.amazon_linux_2023"]

  provisioner "shell" {
    inline = [
      # Update the system
      "sudo dnf update -y",

      # Install Docker
      "sudo dnf install -y git docker",
      "sudo systemctl enable docker",
      "sudo usermod -aG docker ec2-user",

      # Install Docker Compose Plugin
      "export CLI_PLUGINS_PATH=/usr/local/lib/docker/cli-plugins",
      "export DOCKER_COMPOSE_URL=https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)",
      "sudo mkdir -p $CLI_PLUGINS_PATH",
      "sudo curl -SL $DOCKER_COMPOSE_URL -o $CLI_PLUGINS_PATH/docker-compose",
      "sudo chmod +x $CLI_PLUGINS_PATH/docker-compose",

      # Install Dev Containers CLI
      "sudo dnf install -y git nodejs",
      "sudo npm install -g @devcontainers/cli",

      # Install Python modules
      "sudo dnf install -y python3-pip",
      "pip3 install commentjson",

      # Install NGINX
      "sudo dnf install -y nginx",
      "sudo dnf install -y nginx-mod-stream",
      "sudo systemctl enable nginx",
      "sudo systemctl start nginx",

      # Install Certbot
      "sudo dnf install certbot python3-certbot-nginx -y"
    ]
  }
}
