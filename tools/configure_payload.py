#!/usr/bin/env python3
"""Create a configured USB payload without editing the repository templates."""
import argparse
import hashlib
import ipaddress
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEMPLATES = {
    ROOT / 'usb' / 'sraf_dbg.sh': 'sraf_dbg.sh',
    ROOT / 'usb' / 'projector_agent_stable.sh': 'projector_agent_stable.sh',
    ROOT / 'usb' / 'projector_agent_v2_rollback.sh': 'projector_agent_v2_rollback.sh',
    ROOT / 'projector' / 'projector_agent.sh': 'projector_agent.sh',
}


def unique_ports(*items):
    seen = []
    for item in items:
        for part in str(item).split():
            if part and part not in seen:
                seen.append(part)
    return ' '.join(seen)


def configure_text(text, mac_ip, broker_port):
    fallback_ports = unique_ports(broker_port, '2325 2324 2323')
    usb_ports = unique_ports('2323', broker_port, '2325 2324')
    text = text.replace('REPLACE_WITH_MAC_IP', mac_ip)
    text = text.replace('DEFAULT_PORT="2325"', f'DEFAULT_PORT="{broker_port}"')
    text = text.replace('FALLBACK_PORTS="2325 2324 2323"', f'FALLBACK_PORTS="{fallback_ports}"')
    text = text.replace('MAC_PORTS="2323 2325 2324"', f'MAC_PORTS="{usb_ports}"')
    return text


def sha256(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser(description='Build a configured Yaber L2 Plus USB payload.')
    ap.add_argument('mac_ip', help='LAN IP address of the Mac broker, for example 192.168.1.23')
    ap.add_argument('--broker-port', default='2325', help='Mac broker callback port, default 2325')
    ap.add_argument('--out', default='build/usb-root', help='Output folder for files to copy to the USB root')
    args = ap.parse_args()

    try:
        ipaddress.ip_address(args.mac_ip)
    except ValueError as exc:
        raise SystemExit(f'invalid mac_ip: {args.mac_ip!r}') from exc
    port = int(args.broker_port)
    if not (1 <= port <= 65535):
        raise SystemExit('broker port must be 1..65535')
    broker_port = str(port)

    out = (ROOT / args.out).resolve() if not Path(args.out).is_absolute() else Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    written = []
    for src, name in TEMPLATES.items():
        if name == 'projector_agent.sh':
            dst = out / 'manual-projector_agent.sh'
        else:
            dst = out / name
        dst.write_text(configure_text(src.read_text(encoding='utf-8'), args.mac_ip, broker_port), encoding='utf-8')
        dst.chmod(0o755)
        written.append(dst)

    sums = out / 'SHA256SUMS.txt'
    sums.write_text(''.join(f'{sha256(path)}  {path.name}\n' for path in written), encoding='utf-8')
    print(f'Configured USB root written to: {out}')
    print('Copy these files to the FAT32 USB drive root:')
    for path in written:
        if path.name != 'manual-projector_agent.sh':
            print(f'  {path.name}')
    print('Optional inspection copy: manual-projector_agent.sh')
    print('Manifest: SHA256SUMS.txt')


if __name__ == '__main__':
    main()
