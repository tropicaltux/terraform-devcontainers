provider "aws" {
  region = "eu-central-1"
}

# Create key pair in the root file instead of passing key path to modules.
# This reduces resource duplication since the same key pair can be reused.
resource "aws_key_pair" "example_key" {
  key_name   = "example-devcontainer-key"
  public_key = file("~/.ssh/id_ed25519.pub")
}

module "single_devcontainer" {
  name = "single-devcontainer"
  source = "github.com/tropicaltux/terraform-devcontainers"
  devcontainers = [
    {
      source = "https://github.com/microsoft/vscode-remote-try-python.git"
    }
  ]
  public_ssh_key = {
    aws_key_pair_name = aws_key_pair.example_key.key_name
  }
  instance_type = "t2.micro"
}

module "multiple_devcontainers" {
  name = "multiple-devcontainers"
  source = "github.com/tropicaltux/terraform-devcontainers"
  devcontainers = [
    {
      source = "https://github.com/microsoft/vscode-remote-try-node.git"
    },
    {
      source = "https://github.com/microsoft/vscode-remote-try-go.git"
    }
  ]
  public_ssh_key = {
    aws_key_pair_name = aws_key_pair.example_key.key_name
  }
  instance_type = "t2.micro"
}

output "single_devcontainer_module_output" {
  value = module.single_devcontainer
  sensitive = true
}

output "multiple_devcontainers_module_output" {
  value = module.multiple_devcontainers
  sensitive = true
}
