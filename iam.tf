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

# Policy to allow the EC2 instance to get SSM parameters
resource "aws_iam_role_policy" "openvscode_policy" {
  name = "${var.name}-openvscode-policy"
  role = aws_iam_role.openvscode_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["ssm:GetParameter"]
        Effect   = "Allow"
        Resource = [for i, _ in local.prepared_devcontainers : 
                     aws_ssm_parameter.openvscode_tokens[tostring(i)].arn]
      }
    ]
  })
}

# Instance profile to attach the role to the EC2 instance
resource "aws_iam_instance_profile" "openvscode_secrets" {
  name = "${var.name}-openvscode-profile"
  role = aws_iam_role.openvscode_role.name
} 