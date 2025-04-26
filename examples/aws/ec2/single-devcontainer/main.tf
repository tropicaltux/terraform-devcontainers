provider "aws" {
  region = "eu-central-1"
}

module "devcontainers" {
  source = "github.com/tropicaltux/terraform-devcontainers"
  devcontainers = [
    {
      source = "github.com/microsoft/vscode-remote-try-python.git"
    }
  ]
  public_key_path = "~/.ssh/id_rsa.pub"
  instance_type   = "t2.micro"
}

output "devcontainer_module_output" {
  value = module.devcontainers
}
