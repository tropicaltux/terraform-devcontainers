#!/bin/bash
set -e

# Check if SSH_PUBLIC_KEY is set
if [ -z "$SSH_PUBLIC_KEY" ]; then
  echo "Error: SSH_PUBLIC_KEY is not set. Cannot configure SSH access."
  exit 1
fi

# Ensure .ssh directory exists and has correct permissions
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Add the public key to authorized_keys
echo "$SSH_PUBLIC_KEY" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

echo "SSH public key added to authorized_keys file." 