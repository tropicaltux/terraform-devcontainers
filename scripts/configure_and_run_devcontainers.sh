#!/bin/bash

# This script configures nginx and runs the Python script to process devcontainers
# It's called from the Terraform main.tf file

# Get parameters
TMP_DIR="$1"
NAME="$2"
PUBLIC_IP="$3"
SUBDOMAIN_FQDN="$4"

# Make scripts executable
chmod +x ${TMP_DIR}/scripts/generate-self-sing-cert.sh
chmod +x ${TMP_DIR}/scripts/devcontainer_up_with_web_ui.sh
chmod +x ${TMP_DIR}/scripts/clone_repository.sh
chmod +x ${TMP_DIR}/scripts/dns-propagation-check.sh

# Create streams nginx directories
sudo mkdir -p /etc/nginx/streams

# Create letsencrypt directory
sudo mkdir -p /var/www/letsencrypt

# Copy nginx configuration files
sudo cp ${TMP_DIR}/scripts/nginx.config /etc/nginx/nginx.conf
sudo cp ${TMP_DIR}/scripts/ws_params.conf /etc/nginx/conf.d/ws_params.conf

# Generate self-signed SSL certificate for nginx only if not using DNS
if [ -z "${SUBDOMAIN_FQDN}" ]; then 
  sudo PUBLIC_IP=${PUBLIC_IP} ${TMP_DIR}/scripts/generate-self-sing-cert.sh
fi

# Run devcontainers script
DEVCONTAINERS_CMD="python3 ${TMP_DIR}/scripts/run_devcontainers.py --name-prefix=${NAME} --public-ip=${PUBLIC_IP} --scripts-dir=${TMP_DIR}/scripts --config=${TMP_DIR}/devcontainers.json"

# Add high-level domain parameter if SUBDOMAIN_FQDN is provided
if [ -n "${SUBDOMAIN_FQDN}" ]; then
  DEVCONTAINERS_CMD="${DEVCONTAINERS_CMD} --high-level-domain=${SUBDOMAIN_FQDN}"
fi

# Execute the command
eval "${DEVCONTAINERS_CMD}"

# Clean up
rm -rf ${TMP_DIR} 