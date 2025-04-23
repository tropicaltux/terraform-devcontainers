variable "repo_url" {
  description = "Git repository that contains a .devcontainer/ definition."
  type        = string
}

variable "devcontainer_id" {
  description = "Optional devcontainer identifier; if empty a UUID will be generated."
  type        = string
  default     = ""
}

variable "public_key_path" {
  description = "Path to the local *public* SSH key that will be used to create the AWS key pair."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t2.micro"
}

variable "public_key_path" {
  description = "Path to the local public SSH key that will be used to create the AWS key pair."
  type        = string
}
