# Get AWS account ID for ARN construction
data "aws_caller_identity" "current" {}

# Locals variables
locals {
  git_ssh_keys_ssm_arns = [
    for c in local.prepared_devcontainers :
    "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/${c.source.ssh_key.ref}"
    if try(c.source.ssh_key.src, "") == "ssm_parameter_store" && try(c.source.ssh_key.ref, "") != ""
  ]

  git_ssh_keys_secrets_arns = [
    for c in local.prepared_devcontainers :
    "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${c.source.ssh_key.ref}-??????"
    if try(c.source.ssh_key.src, "") == "secrets_manager" && try(c.source.ssh_key.ref, "") != ""
  ]
}

# IAM role for the EC2 instance to access SSM parameters
resource "aws_iam_role" "openvscode_role" {
  name = "${var.name}-openvscode-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Policy to allow the EC2 instance to get OpenVSCode tokens from SSM
resource "aws_iam_role_policy" "openvscode_tokens_policy" {
  name  = "${var.name}-openvscode-tokens-policy"
  role  = aws_iam_role.openvscode_role.id
  count = length(aws_ssm_parameter.openvscode_tokens) > 0 ? 1 : 0

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["ssm:GetParameter"]
        Effect = "Allow"
        Resource = [
          for i, _ in local.prepared_devcontainers :
          aws_ssm_parameter.openvscode_tokens[tostring(i)].arn
        ]
      }
    ]
  })
}

# Policy to allow the EC2 instance to get SSH public keys from SSM
resource "aws_iam_role_policy" "ssh_keys_policy" {
  name  = "${var.name}-ssh-keys-policy"
  role  = aws_iam_role.openvscode_role.id
  count = length(aws_ssm_parameter.container_ssh_public_keys) > 0 ? 1 : 0

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["ssm:GetParameter"]
        Effect   = "Allow"
        Resource = [for k, v in aws_ssm_parameter.container_ssh_public_keys : v.arn]
      }
    ]
  })
}

# Policy to allow the EC2 instance to access Git SSH keys from SSM Parameter Store
resource "aws_iam_role_policy" "git_ssh_keys_policy" {
  name = "${var.name}-git-ssh-keys-policy"
  role = aws_iam_role.openvscode_role.id

  count = (
    length(local.git_ssh_keys_ssm_arns) > 0 || length(local.git_ssh_keys_secrets_arns) > 0
  ) ? 1 : 0

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      length(local.git_ssh_keys_ssm_arns) > 0 ? [
        {
          Action   = ["ssm:GetParameter"]
          Effect   = "Allow"
          Resource = local.git_ssh_keys_ssm_arns
        }
      ] : [],
      length(local.git_ssh_keys_secrets_arns) > 0 ? [
        {
          Action   = ["secretsmanager:GetSecretValue"]
          Effect   = "Allow"
          Resource = local.git_ssh_keys_secrets_arns
        }
      ] : []
    )
  })
}

# Instance profile to attach the role to the EC2 instance
resource "aws_iam_instance_profile" "openvscode_secrets" {
  name = "${var.name}-openvscode-profile"
  role = aws_iam_role.openvscode_role.name
} 