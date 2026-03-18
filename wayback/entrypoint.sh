#!/bin/bash
set -e

# Update config.json with the target date and tolerance
cd /opt/waybackproxy

# Create config.json with our settings
# WaybackProxy uses UPPERCASE keys (DATE, DATE_TOLERANCE, etc.)
python3 -c "
import json
config = {}
try:
    with open('config.json') as f:
        config = json.load(f)
except:
    pass

# Override with uppercase keys (what WaybackProxy actually reads)
config['DATE'] = '${WAYBACK_DATE}'
config['DATE_TOLERANCE'] = int('${TOLERANCE}')
config['QUICK_IMAGES'] = True
config['SILENT'] = False

with open('config.json', 'w') as f:
    json.dump(config, f, indent=2)
print('Config:', json.dumps(config, indent=2))
"

echo "Starting WaybackProxy for date ${WAYBACK_DATE}..."
exec python3 waybackproxy.py
