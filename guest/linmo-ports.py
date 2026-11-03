#!/usr/bin/env python3
import json
import os
import pwd
import socket
import struct
import sys
import threading

PORT = int(os.environ.get("LINMO_PORTS_PORT", "5300"))
DOCKER = os.environ.get("LINMO_DOCKER_SOCKET", "/var/run/docker.sock")
SKIP = {25, 53, 111, 323, 631, 5353, 5355}
SYSTEM = {"systemd-resolve", "systemd-resolved", "cupsd", "avahi-daemon", "rpcbind", "chronyd", "exim4",
          "master", "dnsmasq", "containerd", "spice-vdagentd", "cups-browsed", "rpc.statd"}
LOCAL = {
    "/proc/net/tcp": {"00000000", "0100007F"},
    "/proc/net/tcp6": {"00000000000000000000000000000000", "00000000000000000000000001000000",
                       "0000000000000000FFFF00000100007F"},
}


def log(*args):
    print("[linmo-ports]", *args, file=sys.stderr, flush=True)


def socket_owners(inodes):
    owners = {}
    if not inodes:
        return owners
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            fds = os.listdir(fd_dir)
        except OSError:
            continue
        name = None
        for fd in fds:
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            if not target.startswith("socket:["):
                continue
            inode = target[8:-1]
            if inode in inodes and inode not in owners:
                if name is None:
                    try:
                        with open(f"/proc/{pid}/comm") as f:
                            name = f.read().strip()
                    except OSError:
                        name = ""
                owners[inode] = name
    return owners


def listening():
    found = {}
    for path, local in LOCAL.items():
        try:
            with open(path) as f:
                next(f, None)
                for line in f:
                    parts = line.split()
                    if len(parts) < 10 or parts[3] != "0A":
                        continue
                    addr, port = parts[1].split(":")
                    if addr in local:
                        found.setdefault(int(port, 16), set()).add(parts[9])
        except OSError:
            pass
    owners = socket_owners({inode for inodes in found.values() for inode in inodes})
    ports, names = [], {}
    for port in sorted(found):
        if port in SKIP or port == PORT:
            continue
        name = next((owners[i] for i in found[port] if owners.get(i)), None)
        if name in SYSTEM:
            continue
        ports.append(port)
        if name:
            names[str(port)] = name
    return ports, names


def main_user():
    users = sorted((u for u in pwd.getpwall() if 1000 <= u.pw_uid < 60000), key=lambda u: u.pw_uid)
    return users[0].pw_name if users else None


def recv_exact(sock, n):
    data = b""
    while len(data) < n:
        chunk = sock.recv(n - len(data))
        if not chunk:
            raise EOFError
        data += chunk
    return data


def open_target(port):
    for host in ("127.0.0.1", "::1"):
        try:
            return socket.create_connection((host, port), timeout=5)
        except OSError:
            continue
    return None


def open_docker():
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect(DOCKER)
        return sock
    except OSError:
        return None


def copy(src, dst):
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except OSError:
        pass
    try:
        dst.shutdown(socket.SHUT_WR)
    except OSError:
        pass


def handle(conn):
    try:
        op = recv_exact(conn, 1)
        if op == b"L":
            ports, names = listening()
            conn.sendall(json.dumps({"ports": ports, "names": names, "user": main_user(),
                                     "docker": os.path.exists(DOCKER)}).encode())
            return
        if op in (b"C", b"D"):
            target = open_docker() if op == b"D" else open_target(struct.unpack(">H", recv_exact(conn, 2))[0])
            if target is None:
                return
            target.settimeout(None)
            with target:
                other = threading.Thread(target=copy, args=(target, conn), daemon=True)
                other.start()
                copy(conn, target)
                other.join()
    except (EOFError, OSError, struct.error) as exc:
        log("connection failed:", exc)
    finally:
        conn.close()


def main():
    family = getattr(socket, "AF_VSOCK", None)
    if family is None:
        log("AF_VSOCK is not available")
        return 1
    server = socket.socket(family, socket.SOCK_STREAM)
    server.bind((socket.VMADDR_CID_ANY, PORT))
    server.listen(64)
    log("listening on vsock port", PORT)
    while True:
        conn, _ = server.accept()
        threading.Thread(target=handle, args=(conn,), daemon=True).start()


if __name__ == "__main__":
    sys.exit(main())
