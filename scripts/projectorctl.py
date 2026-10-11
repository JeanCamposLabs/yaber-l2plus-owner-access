#!/usr/bin/env python3
"""CLI for the local projector broker."""
import argparse
import json
import socket
import sys
from pathlib import Path

DEFAULT_SOCKET = Path.cwd() / 'runtime' / 'projector_broker' / 'control.sock'


def request(payload, sock_path):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(str(sock_path))
    s.sendall((json.dumps(payload) + '\n').encode('utf-8'))
    data = b''
    while True:
        chunk = s.recv(65536)
        if not chunk:
            break
        data += chunk
    return json.loads(data.decode('utf-8'))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--socket', default=str(DEFAULT_SOCKET))
    sub = ap.add_subparsers(dest='cmd', required=True)
    sub.add_parser('status')
    c = sub.add_parser('cmd')
    c.add_argument('command', nargs='+')
    c.add_argument('--timeout', type=int, default=20)
    args = ap.parse_args()
    if args.cmd == 'status':
        resp = request({'action': 'status'}, Path(args.socket))
    else:
        resp = request({'action': 'command', 'command': ' '.join(args.command), 'timeout': args.timeout}, Path(args.socket))
    if args.cmd == 'cmd' and 'output' in resp:
        print(resp['output'])
        if not resp.get('ok'):
            print(json.dumps(resp, indent=2), file=sys.stderr)
            sys.exit(2)
        rc = resp.get('returncode')
        sys.exit(rc if isinstance(rc, int) and 0 <= rc <= 255 else 0)
    print(json.dumps(resp, indent=2, sort_keys=True))


if __name__ == '__main__':
    main()
