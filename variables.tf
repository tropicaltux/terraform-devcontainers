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

variable "public_key_path" {
  description = "Path to the local public SSH key that will be used to create the AWS key pair."
  type        = string
}
