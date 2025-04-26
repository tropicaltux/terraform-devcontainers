provider "aws" {
  region = "eu-central-1"
}

module "single_devcontainer" {
  name = "single-devcontainer"
  # source = "github.com/tropicaltux/terraform-devcontainers"
  source = "../../../.."
  devcontainers = [
    {
      source = "https://github.com/microsoft/vscode-remote-try-python.git"
    }
  ]
  public_key_path = "~/.ssh/id_ed25519.pub"
  instance_type   = "t2.micro"
}

module "multiple_devcontainers" {
  name = "multiple-devcontainers"
  # source = "github.com/tropicaltux/terraform-devcontainers"
  source = "../../../.."
  devcontainers = [
    {
      source = "https://github.com/microsoft/vscode-remote-try-node.git"
    },
    {
      source = "https://github.com/microsoft/vscode-remote-try-go.git"
    }
  ]
  public_key_path = "~/.ssh/id_ed25519.pub"
  instance_type   = "t2.micro"
}

output "single_devcontainer_module_output" {
  value = module.single_devcontainer
}

output "multiple_devcontainers_module_output" {
  value = module.multiple_devcontainers
}
