#!/bin/bash
set -e

echo "=== Time Travel Sandbox ==="
echo "Target date: ${TARGET_DATE}"

# --- Fake the system time ---
# libfaketime intercepts time syscalls
# It expects "YYYY-MM-DD HH:MM:SS" format (space separator, not T)
FAKETIME_STR=$(echo "${TARGET_DATE}" | sed 's/T/ /')
export LD_PRELOAD=/usr/lib/x86_64-linux-gnu/faketime/libfaketime.so.1
export FAKETIME="${FAKETIME_STR}"
export FAKETIME_NO_CACHE=1

echo "System time is now: $(date)"

# --- Install MITM CA certificate ---
# Wait for mitmproxy to generate its CA cert, then trust it
# Use --noproxy to bypass the env proxy vars for this specific request
echo "Waiting for MITM proxy CA certificate..."
MAX_WAIT=30
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
    if curl -s --noproxy '*' --proxy http://172.30.0.4:8080 http://mitm.it/cert/pem -o /tmp/mitmproxy-ca.pem 2>/dev/null; then
        if [ -s /tmp/mitmproxy-ca.pem ]; then
            cp /tmp/mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy-ca.crt
            update-ca-certificates 2>/dev/null || true
            echo "MITM CA certificate installed."
            break
        fi
    fi
    sleep 1
    WAITED=$((WAITED + 1))
done

if [ $WAITED -ge $MAX_WAIT ]; then
    echo "WARNING: Could not fetch MITM CA cert. HTTPS may not work."
fi

echo ""
echo "=== Environment Ready ==="
echo "  Fake date:    $(date)"
echo "  HTTP proxy:   172.30.0.3:8888 (WaybackProxy)"
echo "  HTTPS proxy:  172.30.0.4:8080 (mitmproxy → Anthropic API)"
echo ""
echo "Run: python3 /app/claude_client.py"
echo ""

exec "$@"
