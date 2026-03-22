#!/usr/bin/env bash
# fix-gitlab-registry-hsts.sh
# Disables HSTS on GitLab CE Container Registry nginx
# so Docker clients can login via HTTP (local network only)
#
# Run after: sudo gitlab-ctl reconfigure
# Usage: multipass exec gitlab-ce -- sudo bash /tmp/fix-gitlab-registry-hsts.sh

set -euo pipefail

REGISTRY_CONF="/var/opt/gitlab/nginx/conf/service_conf/gitlab-registry.conf"

if [ ! -f "$REGISTRY_CONF" ]; then
  echo "ERROR: $REGISTRY_CONF not found — is GitLab installed?"
  exit 1
fi

if grep -q 'add_header Strict-Transport-Security "max-age=0"' "$REGISTRY_CONF"; then
  echo "HSTS already disabled — no action needed"
  exit 0
fi

sed -i 's/add_header Strict-Transport-Security "max-age=63072000";/add_header Strict-Transport-Security "max-age=0";/' \
  "$REGISTRY_CONF"

gitlab-ctl hup nginx
echo "HSTS disabled on GitLab CE registry"
