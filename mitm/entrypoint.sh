#!/bin/sh
set -e

# Ensure cert directories exist and are writable
mkdir -p /home/mitmproxy/.mitmproxy
echo "Cert directory ready: $(ls -la /home/mitmproxy/)"

echo "Starting mitmproxy with time-travel addon..."
exec mitmdump \
    --listen-host 0.0.0.0 \
    --listen-port 8080 \
    --set confdir=/home/mitmproxy/.mitmproxy \
    --set ssl_insecure=true \
    -s /opt/addon.py \
    --showhost
