provider "aws" {
  region = "eu-central-1"
}

module "devcontainers" {
  source = "github.com/tropicaltux/terraform-devcontainers"
  devcontainers = [
    {
      source = "https://github.com/microsoft/vscode-remote-try-python.git"
    },
    {
      source = "https://github.com/microsoft/vscode-remote-try-node.git"
    },
    {
      source = "https://github.com/microsoft/vscode-remote-try-go.git"
    }
  ]
  public_ssh_key = {
    local_key_path = "~/.ssh/id_ed25519.pub"
  }
  instance_type   = "t2.micro"
}

output "devcontainers_module_output" {
  value = module.devcontainers
  sensitive = true
}
