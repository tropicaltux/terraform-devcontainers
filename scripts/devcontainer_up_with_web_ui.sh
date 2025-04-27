#!/bin/bash

set -e

# Validate required environment variables
required_vars=("DEVCONTAINER_ID" "REPO_URL" "PORT" "SCRIPTS" "OPENVSCODE_TOKEN")
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

DEVCONTAINER_DIR=$HOME/terraform-devcontainers/$DEVCONTAINER_ID
REPO_DIR=$DEVCONTAINER_DIR/repository
WORKSPACE_DIR=$REPO_DIR

# Use DEVCONTAINER_PATH if provided
if [ ! -z "$DEVCONTAINER_PATH" ]; then
  WORKSPACE_DIR=$REPO_DIR/$DEVCONTAINER_PATH
fi

OPENVSCODE_SERVER_DIR=$DEVCONTAINER_DIR/openvscode-server

mkdir -p $REPO_DIR
mkdir -p $OPENVSCODE_SERVER_DIR

# Clone with branch if specified
if [ ! -z "$BRANCH" ]; then
  git clone -b $BRANCH $REPO_URL $REPO_DIR
else
  git clone $REPO_URL $REPO_DIR
fi

cp /home/ec2-user/tmp/terraform-devcontainers/scripts/init-openvscode-server.sh $OPENVSCODE_SERVER_DIR
chmod +x $OPENVSCODE_SERVER_DIR/init-openvscode-server.sh
devcontainer read-configuration --include-merged-configuration --log-format json --workspace-folder $WORKSPACE_DIR 2>/dev/null > $OPENVSCODE_SERVER_DIR/configuration.json

devcontainer up --remove-existing-container --mount "type=bind,source=$OPENVSCODE_SERVER_DIR,target=/tmp/openvscode-server" --workspace-folder $WORKSPACE_DIR

CONTAINER_USER=$(cat $OPENVSCODE_SERVER_DIR/configuration.json | jq -r '.configuration.remoteUser // .mergedConfiguration.remoteUser')
CONTAINER_ID=$(docker ps --filter "label=devcontainer.local_folder=$WORKSPACE_DIR" -q)
OPENVSCODE_SERVER_IP=$(docker inspect -f "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" $CONTAINER_ID)

docker exec --user $CONTAINER_USER -e OPENVSCODE_TOKEN="$OPENVSCODE_TOKEN" $CONTAINER_ID /tmp/openvscode-server/init-openvscode-server.sh

sudo cp $SCRIPTS/ws_params.conf /etc/nginx/conf.d/ws_params.conf

sudo bash -c "OPENVSCODE_SERVER_IP=$OPENVSCODE_SERVER_IP OPENVSCODE_SERVER_PUBLIC_PORT=$PORT envsubst < $SCRIPTS/openvscode-server.template.conf > /etc/nginx/conf.d/$DEVCONTAINER_ID.conf"

echo "OpenVSCode Server for $DEVCONTAINER_ID URL: http://$HOSTNAME:$PORT"

sudo systemctl reload nginx