#!/usr/bin/env python3
"""Durable local broker for the owner's Yaber L2 Plus reverse shell.

The projector connects inbound to the Mac. Local agents talk to this broker over
a Unix domain socket, so they do not need to own the listening terminal session.
"""
import argparse
import json
import os
import selectors
import signal
import socket
import sys
import threading
import time
import traceback
from datetime import datetime, timezone
from pathlib import Path

DEFAULT_RUN_DIR = Path.cwd() / 'runtime' / 'projector_broker'


def utc_now():
    return datetime.now(timezone.utc).isoformat()


class Broker:
    def __init__(self, listen_host, listen_port, control_socket, run_dir, allowed_peer=None):
        self.listen_host = listen_host
        self.listen_port = int(listen_port)
        self.control_socket = Path(control_socket)
        self.run_dir = Path(run_dir)
        self.allowed_peer = allowed_peer
        self.run_dir.mkdir(parents=True, exist_ok=True)
        self.log_path = self.run_dir / 'broker.log'
        self.transcript_path = self.run_dir / 'projector_latest.log'
        self.state_path = self.run_dir / 'state.json'
        self.conn = None
        self.conn_addr = None
        self.conn_lock = threading.RLock()
        self.cmd_lock = threading.Lock()
        self.cond = threading.Condition()
        self.buffer = bytearray()
        self.banner = ''
        self.last_banner = ''
        self.last_connected_at = None
        self.last_disconnected_at = None
        self.bytes_received = 0
        self.shutdown = threading.Event()

    def log(self, msg):
        line = f'{utc_now()} {msg}\n'
        with self.log_path.open('a', encoding='utf-8') as f:
            f.write(line)
        print(line, end='', flush=True)

    def write_state(self):
        state = self.status_dict()
        tmp = self.state_path.with_suffix('.json.tmp')
        tmp.write_text(json.dumps(state, indent=2, sort_keys=True), encoding='utf-8')
        tmp.replace(self.state_path)

    def status_dict(self):
        with self.conn_lock:
            return {
                'time_utc': utc_now(),
                'listen_host': self.listen_host,
                'listen_port': self.listen_port,
                'control_socket': str(self.control_socket),
                'allowed_peer': self.allowed_peer,
                'connected': self.conn is not None,
                'remote': {'host': self.conn_addr[0], 'port': self.conn_addr[1]} if self.conn_addr else None,
                'last_connected_at': self.last_connected_at,
                'last_disconnected_at': self.last_disconnected_at,
                'banner': self.banner[-1000:] if self.conn is not None else '',
                'last_banner': self.last_banner[-1000:],
                'bytes_received': self.bytes_received,
                'pid': os.getpid(),
            }

    def set_conn(self, conn, addr):
        with self.conn_lock:
            if self.conn is not None:
                try:
                    self.conn.close()
                except Exception:
                    pass
            self.conn = conn
            self.conn_addr = addr
            self.banner = ''
            self.buffer.clear()
            self.last_connected_at = utc_now()
            self.bytes_received = 0
            try:
                self.conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            except Exception:
                pass
            self.write_state()
        self.log(f'projector connected from {addr[0]}:{addr[1]}')
        threading.Thread(target=self.reader_loop, args=(conn, addr), daemon=True).start()

    def clear_conn(self, conn, reason):
        with self.conn_lock:
            if self.conn is conn:
                try:
                    conn.close()
                except Exception:
                    pass
                self.last_banner = self.banner
                self.conn = None
                self.conn_addr = None
                self.banner = ''
                self.last_disconnected_at = utc_now()
                self.write_state()
                self.log(f'projector disconnected: {reason}')
        with self.cond:
            self.cond.notify_all()

    def reader_loop(self, conn, addr):
        try:
            while not self.shutdown.is_set():
                try:
                    data = conn.recv(4096)
                except OSError as exc:
                    self.clear_conn(conn, f'recv error {exc}')
                    return
                if not data:
                    self.clear_conn(conn, 'remote closed')
                    return
                text = data.decode('utf-8', 'replace')
                with self.transcript_path.open('a', encoding='utf-8') as f:
                    f.write(text)
                with self.cond:
                    self.buffer.extend(data)
                    self.bytes_received += len(data)
                    if len(self.banner) < 4000:
                        self.banner += text
                    self.cond.notify_all()
        finally:
            self.clear_conn(conn, 'reader loop ended')

    def listen_loop(self):
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind((self.listen_host, self.listen_port))
        srv.listen(5)
        srv.settimeout(1.0)
        self.log(f'listening for projector on {self.listen_host}:{self.listen_port}')
        self.write_state()
        while not self.shutdown.is_set():
            try:
                conn, addr = srv.accept()
            except socket.timeout:
                continue
            except OSError as exc:
                if self.shutdown.is_set():
                    break
                self.log(f'accept error: {exc}')
                time.sleep(1)
                continue
            peer = addr[0]
            if self.allowed_peer and peer != self.allowed_peer:
                self.log(f'rejected connection from {peer}:{addr[1]} because allowed_peer={self.allowed_peer}')
                try:
                    conn.close()
                except Exception:
                    pass
                continue
            self.set_conn(conn, addr)

    def command(self, cmd, timeout=20):
        timeout = max(1, min(int(timeout), 300))
        marker = f'PB_{int(time.time() * 1000)}_{os.getpid()}_{threading.get_ident()}'
        begin = f'__{marker}_BEGIN__'
        end = f'__{marker}_END__'
        wrapped = (
            f"printf '\\n{begin}\\n'\n"
            f"{{\n{cmd}\n}} 2>&1\n"
            f"__pb_rc=$?\n"
            f"printf '\\n{end}:%s\\n' \"$__pb_rc\"\n"
        )
        with self.cmd_lock:
            with self.conn_lock:
                conn = self.conn
            if conn is None:
                return {'ok': False, 'error': 'no projector connection', 'status': self.status_dict()}
            with self.cond:
                self.buffer.clear()
            try:
                conn.sendall(wrapped.encode('utf-8'))
            except OSError as exc:
                self.clear_conn(conn, f'send error {exc}')
                return {'ok': False, 'error': f'send error: {exc}', 'status': self.status_dict()}
            deadline = time.time() + timeout
            raw = b''
            while time.time() < deadline:
                with self.cond:
                    raw = bytes(self.buffer)
                    if end.encode() in raw:
                        break
                    remaining = max(0.05, deadline - time.time())
                    self.cond.wait(min(0.5, remaining))
            raw = bytes(self.buffer)
        text = raw.decode('utf-8', 'replace')
        ok = end in text
        rc = None
        body = text
        if begin in body:
            body = body.split(begin, 1)[1]
        if end in body:
            before, after = body.split(end, 1)
            body = before
            tail = after.splitlines()[0] if after.splitlines() else ''
            if tail.startswith(':'):
                try:
                    rc = int(tail[1:].strip())
                except ValueError:
                    rc = None
        # trim common interactive shell echoes and prompts, but keep evidence
        return {
            'ok': ok,
            'returncode': rc,
            'output': body.strip('\r\n'),
            'raw_tail': text[-2000:],
            'status': self.status_dict(),
        }

    def control_loop(self):
        try:
            self.control_socket.unlink()
        except FileNotFoundError:
            pass
        srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        srv.bind(str(self.control_socket))
        os.chmod(self.control_socket, 0o600)
        srv.listen(20)
        srv.settimeout(1.0)
        self.log(f'control socket ready at {self.control_socket}')
        while not self.shutdown.is_set():
            try:
                client, _ = srv.accept()
            except socket.timeout:
                continue
            except OSError as exc:
                if self.shutdown.is_set():
                    break
                self.log(f'control accept error: {exc}')
                continue
            threading.Thread(target=self.handle_control_client, args=(client,), daemon=True).start()

    def handle_control_client(self, client):
        with client:
            try:
                data = b''
                while b'\n' not in data and len(data) < 1024 * 1024:
                    chunk = client.recv(4096)
                    if not chunk:
                        break
                    data += chunk
                if not data:
                    return
                req = json.loads(data.decode('utf-8'))
                action = req.get('action', 'status')
                if action == 'status':
                    resp = {'ok': True, 'status': self.status_dict()}
                elif action == 'command':
                    resp = self.command(str(req.get('command', '')), req.get('timeout', 20))
                else:
                    resp = {'ok': False, 'error': f'unknown action {action!r}', 'status': self.status_dict()}
            except Exception as exc:
                resp = {'ok': False, 'error': f'{exc}', 'traceback': traceback.format_exc()[-2000:]}
            client.sendall((json.dumps(resp, ensure_ascii=False) + '\n').encode('utf-8'))

    def stop(self, *_):
        self.shutdown.set()
        with self.conn_lock:
            if self.conn is not None:
                try:
                    self.conn.close()
                except Exception:
                    pass

    def run(self):
        signal.signal(signal.SIGTERM, self.stop)
        signal.signal(signal.SIGINT, self.stop)
        threading.Thread(target=self.control_loop, daemon=True).start()
        self.listen_loop()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--listen-host', default='0.0.0.0')
    ap.add_argument('--listen-port', type=int, default=2325)
    ap.add_argument('--run-dir', default=str(DEFAULT_RUN_DIR))
    ap.add_argument('--control-socket', default=None)
    ap.add_argument('--allowed-peer', default=None)
    args = ap.parse_args()
    control_socket = args.control_socket or str(Path(args.run_dir) / 'control.sock')
    Broker(args.listen_host, args.listen_port, control_socket, args.run_dir, args.allowed_peer).run()


if __name__ == '__main__':
    main()
