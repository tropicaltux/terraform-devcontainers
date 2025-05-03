############### devcontainer ##################################################

variable "devcontainers" {
  description = "Git repositories that contain devcontainer definitions."
  type = list(object({
    id = optional(string)
    source = object({
      url               = string
      branch            = optional(string)
      devcontainer_path = optional(string)
      ssh_key = optional(object({
        ref = string
        src = string # either 'secrets_manager' or 'ssm_parameter_store'
      }))
    })
    remote_access = optional(object({
      openvscode_server = optional(object({
        port = optional(number)
      }))
      ssh = optional(object({
        port = optional(number)
        public_ssh_key = optional(object({
          local_key_path    = optional(string)
          aws_key_pair_name = optional(string)
        }))
      }))
      }), {
      openvscode_server = {}
    })
  }))

  # Source must be set for every repo
  validation {
    condition     = alltrue([for c in var.devcontainers : c.source.url != "" && c.source.url != null])
    error_message = "The *source.url* attribute is mandatory for every devcontainer."
  }

  # SSH key validation for source URL
  validation {
    condition = alltrue([
      for c in var.devcontainers : (
        (strcontains(c.source.url, "ssh://") || strcontains(c.source.url, "git@"))
        ? contains(keys(c.source), "ssh_key")
        : !contains(keys(c.source), "ssh_key") || c.source.ssh_key == null
      )
    ])
    error_message = "ssh_key must be provided for SSH URLs, and omitted for HTTPS URLs."
  }

  # Validate ssh_key src field
  validation {
    condition = alltrue([
      for c in var.devcontainers : (
        try(c.source.ssh_key, null) == null ? true :
        contains(["secrets_manager", "ssm_parameter_store"], c.source.ssh_key.src)
      )
    ])
    error_message = "The ssh_key.src value must be either 'secretsmanager' or 'ssm'."
  }

  # Number of devcontainers must be between 1 and 1000
  validation {
    condition     = length(var.devcontainers) >= 1 && length(var.devcontainers) <= 512
    error_message = "The number of devcontainers must be between 1 and 512."
  }

  # All declared ports (VS Code & SSH) must be in range 1024-65535
  validation {
    condition = alltrue(flatten([
      for c in var.devcontainers : [
        for p in [
          try(c.remote_access.openvscode_server.port, null),
          try(c.remote_access.ssh.port, null)
        ] : p == null ? true : (p >= 1024 && p <= 65535)
      ]
    ]))
    error_message = "Every OpenVSCode-server or SSH port must be between 1024 and 65535."
  }

  # All ports must be *unique* across the whole list
  validation {
    condition = (
      length(distinct(compact(flatten([
        [for c in var.devcontainers : try(c.remote_access.openvscode_server.port, null)],
        [for c in var.devcontainers : try(c.remote_access.ssh.port, null)]
        ])))) == length(compact(flatten([
        [for c in var.devcontainers : try(c.remote_access.openvscode_server.port, null)],
        [for c in var.devcontainers : try(c.remote_access.ssh.port, null)]
      ])))
    )
    error_message = "Ports (both OpenVSCode and SSH) must be unique across all devcontainers."
  }

  # Exactly one key field per-SSH config
  validation {
    condition = alltrue([
      for c in var.devcontainers : (
        try(c.remote_access.ssh.public_ssh_key, null) == null ? true :
        length(compact([
          try(c.remote_access.ssh.public_ssh_key.local_key_path, null),
          try(c.remote_access.ssh.public_ssh_key.aws_key_pair_name, null)
        ])) == 1
      )
    ])
    error_message = "In every SSH block specify *either* local_key_path *or* aws_key_pair_name (not both)."
  }
}

############### name ##########################################################
variable "name" {
  description = "Name prefix for the resources."
  type        = string
  default     = "devcontainers"
}

############### instance_type #################################################
variable "instance_type" {
  description = "EC2 instance type."
  type        = string
}

############### public_ssh_key #################################################
variable "public_ssh_key" {
  description = "Provide either the path to a local public SSH key or the name of an existing AWS key pair. Only one option should be set."
  type = object({
    local_key_path    = optional(string)
    aws_key_pair_name = optional(string)
  })

  validation {
    condition = length(compact([
      try(var.public_ssh_key.local_key_path, null),
      try(var.public_ssh_key.aws_key_pair_name, null)
    ])) == 1
    error_message = "Exactly one of local_key_path or aws_key_pair_name must be supplied."
  }
}
