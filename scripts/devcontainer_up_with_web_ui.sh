#!/bin/bash

set -e

DEVCONTAINER_DIR=$HOME/project-x/$DEVCONTAINER_ID
REPO_DIR=$DEVCONTAINER_DIR/repository
WORKSPACE_DIR=$REPO_DIR
OPENVSCODE_SERVER_DIR=$DEVCONTAINER_DIR/openvscode-server

mkdir -p $REPO_DIR
mkdir -p $OPENVSCODE_SERVER_DIR

git clone $REPO_URL $REPO_DIR

cp /home/ec2-user/tmp/project-x/scripts/init-openvscode-server.sh $OPENVSCODE_SERVER_DIR
chmod +x $OPENVSCODE_SERVER_DIR/init-openvscode-server.sh
devcontainer read-configuration --include-merged-configuration --log-format json --workspace-folder $WORKSPACE_DIR 2>/dev/null > $OPENVSCODE_SERVER_DIR/configuration.json

devcontainer up --remove-existing-container --mount "type=bind,source=$OPENVSCODE_SERVER_DIR,target=/tmp/openvscode-server" --workspace-folder $WORKSPACE_DIR

CONTAINER_USER=$(cat $OPENVSCODE_SERVER_DIR/configuration.json | jq -r '.configuration.remoteUser // .mergedConfiguration.remoteUser')
CONTAINER_ID=$(docker ps --filter "label=devcontainer.local_folder=$WORKSPACE_DIR" -q)
OPENVSCODE_SERVER_IP=$(docker inspect -f "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" $CONTAINER_ID)

docker exec --user $CONTAINER_USER $CONTAINER_ID /tmp/openvscode-server/init-openvscode-server.sh

sudo cp $SCRIPTS/ws_params.conf /etc/nginx/conf.d/ws_params.conf

sudo bash -c "OPENVSCODE_SERVER_IP=$OPENVSCODE_SERVER_IP OPENVSCODE_SERVER_PUBLIC_PORT=8000 envsubst < $SCRIPTS/openvscode-server.template.conf > /etc/nginx/conf.d/$DEVCONTAINER_ID.conf"

echo "OpenVSCode Server local URL: http://$OPENVSCODE_SERVER_IP:8000"

sudo systemctl reload nginx