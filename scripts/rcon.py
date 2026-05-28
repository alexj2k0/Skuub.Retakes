#!/usr/bin/env python3
"""Send RCON commands to the CS:GO server."""
import socket
import struct
import sys
import os

HOST = os.environ.get("RCON_HOST", "127.0.0.1")
PORT = int(os.environ.get("RCON_PORT", "27015"))

PASSWORD_FILE = "/home/steam/csgo-legacy/csgo/cfg/private/rcon_password.cfg"

def get_password():
    if "RCON_PASSWORD" in os.environ:
        return os.environ["RCON_PASSWORD"]
    try:
        with open(PASSWORD_FILE) as f:
            for line in f:
                if "rcon_password" in line:
                    val = line.split('"', 2)
                    if len(val) >= 2:
                        return val[1]
    except Exception:
        pass
    sys.exit("RCON password not found (set RCON_PASSWORD env or ensure rcon_password.cfg exists)")

PASSWORD = get_password()

SERVERDATA_AUTH = 3
SERVERDATA_EXECCOMMAND = 2

def send(sock, packet_id, packet_type, body):
    size = 10 + len(body)
    sock.send(struct.pack('<iii', size, packet_id, packet_type) + body.encode() + b'\x00\x00')

def recv(sock):
    size = struct.unpack('<i', sock.recv(4))[0]
    packet_id = struct.unpack('<i', sock.recv(4))[0]
    packet_type = struct.unpack('<i', sock.recv(4))[0]
    body = b''
    remaining = size - 8
    while remaining > 0:
        chunk = sock.recv(min(4096, remaining))
        if not chunk:
            break
        body += chunk
        remaining -= len(chunk)
    return packet_id, packet_type, body[:-2].decode(errors='replace')

def rcon(command):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(5)
    sock.connect((HOST, PORT))
    try:
        send(sock, 1, SERVERDATA_AUTH, PASSWORD)
        pid, ptype, body = recv(sock)
        if pid == -1:
            sys.exit(f"RCON auth failed: {body}")
        send(sock, 2, SERVERDATA_EXECCOMMAND, command)
        send(sock, 3, SERVERDATA_EXECCOMMAND, " ")
        response = []
        while True:
            pid, ptype, body = recv(sock)
            if pid == 3:
                break
            if body:
                response.append(body)
        print('\n'.join(response).strip())
    finally:
        sock.close()

if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit("Usage: rcon.py <command>")
    rcon(' '.join(sys.argv[1:]))
