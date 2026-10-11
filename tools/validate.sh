#!/bin/sh
set -eu

python3 -m py_compile scripts/projector_broker.py scripts/projectorctl.py tools/configure_payload.py
python3 - <<'PY'
from pathlib import Path
for cache in Path('.').rglob('__pycache__'):
    for child in cache.iterdir():
        child.unlink()
    cache.rmdir()
PY
/bin/sh -n projector/projector_agent.sh
/bin/sh -n projector/remove_owner_access.sh
/bin/sh -n usb/sraf_dbg.sh
/bin/sh -n usb/projector_agent_stable.sh
/bin/sh -n usb/projector_agent_v2_rollback.sh
if command -v plutil >/dev/null 2>&1; then
  plutil -lint templates/com.projector.broker.plist.template >/dev/null
fi

python3 tools/configure_payload.py 192.0.2.23 --broker-port 2325 --out build/validate-usb >/dev/null
/bin/sh -n build/validate-usb/sraf_dbg.sh
/bin/sh -n build/validate-usb/projector_agent_stable.sh
/bin/sh -n build/validate-usb/projector_agent_v2_rollback.sh
/bin/sh -n build/validate-usb/manual-projector_agent.sh
python3 - <<'PY'
from pathlib import Path
for path in Path('build/validate-usb').glob('*'):
    text = path.read_text(errors='ignore')
    if 'REPLACE_WITH_MAC_IP' in text:
        raise SystemExit(f'unreplaced placeholder in {path}')
PY

python3 - <<'PY'
from pathlib import Path
import re
literal_patterns = ['serialNumber', chr(47) + 'Users' + chr(47), 'gmail', 'outlook', 'PROJECTOR PROJECT']
email = re.compile(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}')
private_10 = re.compile(r'\b10\.\d{1,3}\.\d{1,3}\.\d{1,3}\b')
for path in Path('.').rglob('*'):
    if not path.is_file() or '.git' in path.parts or 'build' in path.parts or str(path) == 'tools/validate.sh':
        continue
    text = path.read_text(errors='ignore')
    if email.search(text):
        raise SystemExit(f'email-like string found in {path}')
    if private_10.search(text):
        raise SystemExit(f'10.x private IP found in {path}')
    for pattern in literal_patterns:
        if pattern in text:
            raise SystemExit(f'sensitive pattern {pattern!r} found in {path}')
PY

echo "validation ok"
