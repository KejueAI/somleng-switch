#!/bin/bash

set -e

if [ "$1" = 'freeswitch' ]; then
  # Local constants
  FS_CONTAINER_CONFIG_DIRECTORY="/etc/freeswitch/"

  FS_CONTAINER_BINARY="/usr/bin/freeswitch"
  FS_USER="freeswitch"
  FS_GROUP="daemon"

  export_fs_env_vars "$FS_CONTAINER_CONFIG_DIRECTORY/env.xml"

  # Setup directories

  for directory in "$FS_LOG_DIRECTORY" "$FS_CONTAINER_CONFIG_DIRECTORY" "$FS_STORAGE_DIRECTORY" "$FS_TTS_CACHE_DIRECTORY"
  do
    mkdir -p "$directory"
    chown "$FS_USER:$FS_GROUP" "$directory"
  done

  # Set up TLS certificates directory for SIP TLS support.
  # If /tls-certs is mounted (from a Kubernetes secret), copy certs into
  # the location FreeSWITCH expects: $base_dir/certs/ (i.e. /usr/lib/freeswitch/certs/).
  # FreeSWITCH requires: agent.pem (combined cert+key) and cafile.pem (CA chain).
  FS_CERTS_DIR="/usr/lib/freeswitch/certs"
  mkdir -p "$FS_CERTS_DIR"
  if [ -d "/tls-certs" ] && [ "$(ls -A /tls-certs 2>/dev/null)" ]; then
    cp /tls-certs/* "$FS_CERTS_DIR/"
    chmod 600 "$FS_CERTS_DIR"/*.pem 2>/dev/null || true
  fi
  chown -R "$FS_USER:$FS_GROUP" "$FS_CERTS_DIR"

  # execute FreeSWITCH
  exec "$FS_CONTAINER_BINARY" -u "$FS_USER" -g "$FS_GROUP" -nonat -storage "$FS_STORAGE_DIRECTORY"
fi

exec "$@"
