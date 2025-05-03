#!/bin/bash
set -e

# Check required environment variables
required_vars=("REPO_URL" "REPO_DEST_PATH")
missing_vars=()

for var in "${required_vars[@]}"; do
  if [ -z "${!var}" ]; then
    missing_vars+=("$var")
  fi
done

if [ ${#missing_vars[@]} -ne 0 ]; then
  echo "ERROR: The following required environment variables are not set:"
  for var in "${missing_vars[@]}"; do
    echo "  - $var"
  done
  exit 1
fi

# Handle SSH or HTTPS repository URLs
if [[ "$REPO_URL" == *ssh://* || "$REPO_URL" == *git@* ]]; then
  if [ -z "$SECRET_NAME" ] || [ -z "$SOURCE" ]; then
    echo "ERROR: SSH repository URL detected but SECRET_NAME and/or SOURCE not provided."
    exit 1
  fi
  
  echo "Cloning repository using SSH authentication..."
  
  # Start ssh-agent
  eval $(ssh-agent -s)

  # Get the SSH key and add it to ssh-agent
  if [ "$SOURCE" = "secrets_manager" ]; then
    aws secretsmanager get-secret-value \
      --secret-id "$SECRET_NAME" \
      --query SecretString \
      --output text | ssh-add -
  elif [ "$SOURCE" = "ssm_parameter_store" ]; then
    aws ssm get-parameter \
      --name "$SECRET_NAME" \
      --with-decryption \
      --query Parameter.Value \
      --output text | ssh-add -
  else
    echo "ERROR: Unsupported source: $SOURCE. Must be 'secrets_manager' or 'ssm_parameter_store'."
    ssh-agent -k
    exit 1
  fi

  # Clone repository with branch if specified
  if [ ! -z "$BRANCH" ]; then
    GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
    git -C "$REPO_DEST_PATH" clone -b "$BRANCH" "$REPO_URL"
  else
    GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
    git -C "$REPO_DEST_PATH" clone "$REPO_URL"
  fi

  # Kill the ssh-agent to avoid leaving keys in memory
  ssh-agent -k
else
  # Standard clone for HTTPS URLs
  echo "Cloning repository using HTTPS..."
  if [ ! -z "$BRANCH" ]; then
    git -C "$REPO_DEST_PATH" clone -b "$BRANCH" "$REPO_URL"
  else
    git -C "$REPO_DEST_PATH" clone "$REPO_URL"
  fi
fi

exit 0 