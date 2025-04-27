#!/bin/bash

# generate a self-signed TLS certificate for an IP address
#
# Environment variables:
#   PUBLIC_IP      – required, e.g. 203.0.113.10

set -e

if [ -z "$PUBLIC_IP" ]; then
    echo "Error: venv PUBLIC_IP is not set." >&2
    exit 1
fi

VALIDITY_DAYS="365"
DEST_DIR="/etc/nginx/ssl"
CRT_NAME="nginx-self-signed.crt"
KEY_NAME="nginx-self-signed.key"

echo "Generating a ${VALIDITY_DAYS}-day self-signed certificate for ${PUBLIC_IP} …"
openssl req -x509 -nodes -days "${VALIDITY_DAYS}" \
  -newkey rsa:2048 \
  -keyout  "${KEY_NAME}" \
  -out     "${CRT_NAME}" \
  -subj    "/CN=${PUBLIC_IP}" \
  -addext  "subjectAltName=IP:${PUBLIC_IP}"

echo "Creating target directory ${DEST_DIR} (if absent) …"
install -d -m 700 "${DEST_DIR}"

echo "Installing certificate and key with strict permissions …"
install -m 600 "${KEY_NAME}" "${DEST_DIR}/"
install -m 644 "${CRT_NAME}" "${DEST_DIR}/"

echo "Done!"
echo "  • Key         : ${DEST_DIR}/${KEY_NAME}"
echo "  • Certificate : ${DEST_DIR}/${CRT_NAME}"
