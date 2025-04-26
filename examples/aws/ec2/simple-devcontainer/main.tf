provider "aws" {
  region = "eu-central-1"
}

module "devcontainer" {
  source = "github.com/tropicaltux/terraform-devcontainers"
  devcontainers = [
    {
      source = "https://github.com/microsoft/vscode-remote-try-python.git"
    }
  ]
  public_ssh_key = {
    local_key_path = "~/.ssh/id_ed25519.pub"
  }
  instance_type   = "t2.micro"
}

output "devcontainer_module_output" {
  value = module.devcontainer
  sensitive = true
}
