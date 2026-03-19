#!/bin/bash
set -e

# Convert TARGET_DATE from ISO format (with T) to faketime format (with space)
TARGET_STR=$(echo "${TARGET_DATE}" | sed 's/T/ /')
export FAKETIME="@${TARGET_STR}"

# Persist FAKETIME for any future shells (docker exec, su, etc.)
# This ensures every bash session in the container gets the fake time
echo "export FAKETIME=\"@${TARGET_STR}\"" > /etc/profile.d/faketime.sh
echo "export FAKETIME=\"@${TARGET_STR}\"" >> /etc/bash.bashrc

# Verify it works
TEST_DATE=$(date +%Y)
if [ "$TEST_DATE" = "2010" ]; then
    echo "Time simulation active: $(date)"
else
    echo "WARNING: faketime not working. date reports year=$TEST_DATE"
    echo "  LD_PRELOAD=$LD_PRELOAD"
    echo "  FAKETIME=$FAKETIME"
fi

# Fetch MITM CA cert — temporarily unset LD_PRELOAD so curl
# doesn't have TLS issues with a 2010 clock
SAVED_PRELOAD="$LD_PRELOAD"
unset LD_PRELOAD

MAX_WAIT=30
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
    if curl -s --noproxy '*' --proxy http://172.30.0.4:8080 http://mitm.it/cert/pem -o /tmp/mitmproxy-ca.pem 2>/dev/null; then
        if [ -s /tmp/mitmproxy-ca.pem ]; then
            cp /tmp/mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy-ca.crt
            update-ca-certificates 2>/dev/null || true
            break
        fi
    fi
    sleep 1
    WAITED=$((WAITED + 1))
done
rm -f /tmp/mitmproxy-ca.pem

# Restore LD_PRELOAD
export LD_PRELOAD="$SAVED_PRELOAD"

echo ""
exec "$@"
