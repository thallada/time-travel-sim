#!/bin/sh
set -e

# Resolve the real IP of api.anthropic.com at startup
# so we can allowlist it through real DNS
ANTHROPIC_IP=$(dig +short api.anthropic.com @8.8.8.8 | head -1)
echo "Resolved api.anthropic.com -> $ANTHROPIC_IP"

cat > /etc/dnsmasq.conf <<EOF
# Don't use /etc/resolv.conf
no-resolv

# Upstream DNS for allowlisted domains (Anthropic API)
server=8.8.8.8

# Redirect ALL domains to the MITM proxy by default
address=/#/172.30.0.4

# EXCEPT: let Anthropic API resolve to its real IP
host-record=api.anthropic.com,$ANTHROPIC_IP

# Log queries for debugging
log-queries
log-facility=-

# Listen on all interfaces
interface=*

# Don't cache (we want fresh Anthropic lookups)
cache-size=0
EOF

echo "Starting dnsmasq..."
exec dnsmasq --no-daemon
