variable "devcontainers" {
  description = "List of git repositories with devcontainer definitions to be run."
  type = list(object({
    id                = optional(string)
    source            = string
    branch            = optional(string)
    devcontainer_path = optional(string)
    port              = optional(number)
  }))

  validation {
    condition     = length([for c in var.devcontainers : c if c.source == ""]) == 0
    error_message = "The source attribute must be provided for all devcontainers."
  }

  # Validate that specified ports are unique
  validation {
    condition = length(
      distinct([for c in var.devcontainers : c.port if c.port != null])
      ) == length(
      [for c in var.devcontainers : c.port if c.port != null]
    )
    error_message = "All specified ports must be unique across devcontainers."
  }

  # Validate that specified ports are in a reasonable range
  validation {
    condition = alltrue([
      for c in var.devcontainers : (
        c.port == null ? true : (c.port >= 1024 && c.port <= 65535)
      )
    ])
    error_message = "All specified ports must be between 1024 and 65535."
  }
}

variable "name" {
  description = "Name prefix for the resources."
  type        = string
  default     = "devcontainers"
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
}

variable "public_ssh_key" {
  description = "Provide either the path to a local public SSH key or the name of an existing AWS key pair. Only one option should be set."
  type = object({
    local_key_path    = optional(string)
    aws_key_pair_name = optional(string)
  })

  validation {
    condition = (
      (try(var.public_ssh_key.local_key_path, null) != null && try(var.public_ssh_key.aws_key_pair_name, null) == null) ||
      (try(var.public_ssh_key.local_key_path, null) == null && try(var.public_ssh_key.aws_key_pair_name, null) != null)
    )
    error_message = "Exactly one of local_key_path or aws_key_pair_name must be provided in public_ssh_key."
  }
}
