#!/bin/sh

exec /opt/keycloak/bin/kc.sh start \
  --optimized \
  --http-enabled=true \
  --http-port=${PORT:-8080}