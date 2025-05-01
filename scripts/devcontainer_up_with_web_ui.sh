#!/bin/bash

set -e

# Validate required environment variables
required_vars=("DEVCONTAINER_ID" "REPO_URL" "SCRIPTS" "PUBLIC_IP" "OPENVSCODE_SERVER_ENABLED" "SSH_ENABLED")
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

if [ "${OPENVSCODE_SERVER_ENABLED}" = "true" ]; then
  if [ -z "${OPENVSCODE_SERVER_PORT}" ]; then
    echo "ERROR: OpenVSCode Server is enabled but OPENVSCODE_SERVER_PORT is not set."
    exit 1
  fi
  
  if [ -z "${OPENVSCODE_TOKEN}" ]; then
    echo "ERROR: OpenVSCode Server is enabled but OPENVSCODE_TOKEN is not set."
    exit 1
  fi
fi

if [ "${SSH_ENABLED}" = "true" ]; then
  if [ -z "${SSH_PUBLIC_KEY}" ]; then
    echo "ERROR: SSH is enabled but SSH_PUBLIC_KEY is not set."
    exit 1
  fi
  
  if [ -z "${SSH_PORT}" ]; then
    echo "ERROR: SSH is enabled but SSH_PORT is not set."
    exit 1
  fi
fi

DEVCONTAINER_DEST_PATH=$HOME/terraform-devcontainers/$DEVCONTAINER_ID
REPO_DEST_PATH=$DEVCONTAINER_DEST_PATH/repository

INIT_SCRIPTS_PATH=$DEVCONTAINER_DEST_PATH/init-scripts

mkdir -p $REPO_DEST_PATH
mkdir -p $INIT_SCRIPTS_PATH

# Clone with branch if specified
if [ ! -z "$BRANCH" ]; then
  git -C $REPO_DEST_PATH clone -b $BRANCH $REPO_URL
else
  git -C $REPO_DEST_PATH clone $REPO_URL
fi

REPO_DIR=$(basename "$(find $REPO_DEST_PATH -mindepth 1 -maxdepth 1 -type d)")
WORKSPACE_PATH=$REPO_DEST_PATH/$REPO_DIR
# Use DEVCONTAINER_PATH if provided
if [ ! -z "$DEVCONTAINER_PATH" ]; then
  WORKSPACE_PATH=$WORKSPACE_PATH/$DEVCONTAINER_PATH
fi

devcontainer read-configuration --include-merged-configuration --log-format json --workspace-folder $WORKSPACE_PATH 2>/dev/null > $INIT_SCRIPTS_PATH/configuration.json

# Only copy and prepare OpenVSCode server script if enabled
if [ "${OPENVSCODE_SERVER_ENABLED}" = "true" ]; then
  cp /home/ec2-user/tmp/terraform-devcontainers/scripts/init-openvscode-server.sh $INIT_SCRIPTS_PATH
  chmod +x $INIT_SCRIPTS_PATH/init-openvscode-server.sh
fi

# Add SSH Feature to devcontainer.json if SSH key is provided
if [ "${SSH_ENABLED}" = "true" ]; then
  echo "SSH key provided, adding SSHD feature to devcontainer.json"
  
  # Create backup of the devcontainer.json file
  DEVCONTAINER_JSON="${WORKSPACE_PATH}/.devcontainer/devcontainer.json"
  if [ -f "$DEVCONTAINER_JSON" ]; then
    cp "$DEVCONTAINER_JSON" "${DEVCONTAINER_JSON}.backup"
    echo "Created backup of devcontainer.json at ${DEVCONTAINER_JSON}.backup."
  fi

  python3 ${SCRIPTS}/add_sshd_feature.py --workspace="${WORKSPACE_PATH}"
  
  # Copy SSH key initialization script
  cp /home/ec2-user/tmp/terraform-devcontainers/scripts/init-ssh-key.sh $INIT_SCRIPTS_PATH
  chmod +x $INIT_SCRIPTS_PATH/init-ssh-key.sh
fi

devcontainer up --remove-existing-container --mount "type=bind,source=$INIT_SCRIPTS_PATH,target=/tmp/init-scripts" --workspace-folder $WORKSPACE_PATH

# Restore the original devcontainer.json if a backup was made
if [ "${SSH_ENABLED}" = "true" ] && [ -f "${DEVCONTAINER_JSON}.backup" ]; then
  echo "Restoring original devcontainer.json from backup."
  mv "${DEVCONTAINER_JSON}.backup" "${DEVCONTAINER_JSON}"
fi

CONTAINER_USER=$(cat $INIT_SCRIPTS_PATH/configuration.json | jq -r '.configuration.remoteUser // .mergedConfiguration.remoteUser')
CONTAINER_WORKSPACE_PATH=$(cat $INIT_SCRIPTS_PATH/configuration.json | jq -r '.workspace.workspaceFolder')
CONTAINER_ID=$(docker ps --filter "label=devcontainer.local_folder=$WORKSPACE_PATH" -q)
CONTAINER_IP=$(docker inspect -f "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" $CONTAINER_ID)

# Only set up OpenVSCode server if enabled
if [ "${OPENVSCODE_SERVER_ENABLED}" = "true" ]; then
  echo "Setting up OpenVSCode Server for $DEVCONTAINER_ID..."
  
  # Execute the OpenVSCode server initialization script
  docker exec --user $CONTAINER_USER -e OPENVSCODE_TOKEN="$OPENVSCODE_TOKEN" $CONTAINER_ID /tmp/init-scripts/init-openvscode-server.sh
  
  # Configure nginx for OpenVSCode server
  sudo bash -c "
    env \
      OPENVSCODE_SERVER_IP=$CONTAINER_IP \
      OPENVSCODE_SERVER_PUBLIC_PORT=$OPENVSCODE_SERVER_PORT \
      WORKSPACE_PATH=$CONTAINER_WORKSPACE_PATH \
      PUBLIC_IP=$PUBLIC_IP \
    envsubst '\$OPENVSCODE_SERVER_IP \$OPENVSCODE_SERVER_PUBLIC_PORT \$WORKSPACE_PATH' \
      < $SCRIPTS/openvscode-server.template.conf \
      > /etc/nginx/conf.d/$DEVCONTAINER_ID.conf
  "
  
  echo "OpenVSCode Server for $DEVCONTAINER_ID URL: https://$CONTAINER_IP:$OPENVSCODE_SERVER_PORT"
else
  echo "OpenVSCode Server is disabled, skipping installation."
fi

# Execute SSH key initialization script if SSH is enabled
if [ "${SSH_ENABLED}" = "true" ]; then
  echo "Setting up SSH access for the container..."
  
  # Configure SSH on the container
  docker exec --user $CONTAINER_USER -e SSH_PUBLIC_KEY="$SSH_PUBLIC_KEY" $CONTAINER_ID /tmp/init-scripts/init-ssh-key.sh
  
  # Configure nginx SSH stream
  sudo bash -c "
    env \
      SSH_CONTAINER_IP=$CONTAINER_IP \
      SSH_PUBLIC_PORT=$SSH_PORT \
      CONTAINER_SSH_PORT=2222 \
    envsubst '\$SSH_CONTAINER_IP \$SSH_PUBLIC_PORT \$CONTAINER_SSH_PORT' \
      < $SCRIPTS/ssh-stream.template.conf \
      > /etc/nginx/streams/$DEVCONTAINER_ID.conf
  "
  
  echo "SSH access for $DEVCONTAINER_ID configured on port $SSH_PORT"
fi

# Reload nginx to apply new configurations
sudo systemctl reload nginx