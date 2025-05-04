#!/bin/bash

set -e

DOMAIN=$1
RECORD_TYPE="A"
DNS_SERVERS=("8.8.8.8" "1.1.1.1" "9.9.9.9")

while true; do
  echo "Checking DNS for $DOMAIN..."
  for SERVER in "${DNS_SERVERS[@]}"; do
    RESULT=$(dig @$SERVER $DOMAIN $RECORD_TYPE +short)
    if [[ -n "$RESULT" ]]; then
      echo "[$(date)] DNS record found on server $SERVER: $RESULT"
      exit 0
    else
      echo "[$(date)] DNS record not yet found on server $SERVER"
    fi
  done
  sleep 60
done
