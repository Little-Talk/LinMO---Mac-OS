#!/usr/bin/env python3
import base64, json, os, socket, struct, subprocess, sys, tempfile, time, zlib

H = struct.Struct("<IH")
BINARY_KINDS = (4, 7, 8, 9)
binary = os.path.abspath(sys.argv[1])
work = tempfile.mkdtemp(prefix="linmo-test-")
home = os.path.join(work, "home")
runtime = os.path.join(work, "xdg"); os.makedirs(runtime, mode=0o700)


def write_png(path, size):
    row = b"\x00" + b"\x00\x80\xff\xff" * size
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(row * size)) + chunk(b"IEND", b""))


apps_dir = os.path.join(home, ".local/share/applications"); os.makedirs(apps_dir)
icon_dir = os.path.join(home, ".local/share/icons/hicolor/48x48/apps"); os.makedirs(icon_dir)
with open(os.path.join(apps_dir, "linmo-xterm.desktop"), "w") as f:
    f.write("[Desktop Entry]\nType=Application\nName=LinMO XTerm\nExec=xterm -class LinmoXterm -e sh\n"
            "Icon=linmo-xterm-icon\nStartupWMClass=LinmoXterm\n")
write_png(os.path.join(icon_dir, "linmo-xterm-icon.png"), 32)

sock_path = os.path.join(work, "mac.sock")
srv = socket.socket(socket.AF_UNIX); srv.bind(sock_path); srv.listen(1)
env = dict(os.environ, XDG_RUNTIME_DIR=runtime, LINMO_AGENT_UNIX=sock_path, HOME=home, LANG="C.UTF-8")
env.pop("DISPLAY", None); env.pop("WAYLAND_DISPLAY", None)
comp = subprocess.Popen([binary], env=env)
srv.settimeout(10); conn, _ = srv.accept(); conn.settimeout(0.2)
buf = bytearray(); failures = []


def recv(pred, timeout=8):
    global buf
    end, out = time.time() + timeout, []
    while time.time() < end:
        while len(buf) >= 6:
            n, k = H.unpack_from(buf)
            if len(buf) < 6 + n: break
            p = bytes(buf[6:6 + n]); del buf[:6 + n]
            m = (k, p if k in BINARY_KINDS else json.loads(p)); out.append(m)
            if pred(m): return out
        try: data = conn.recv(1 << 20)
        except socket.timeout: continue
        if not data: break
        buf += data
    return out


def send(k, o):
    p = json.dumps(o).encode(); conn.sendall(H.pack(len(p), k) + p)


def check(name, ok):
    print(("PASS " if ok else "FAIL ") + name, flush=True)
    if not ok: failures.append(name)


recv(lambda m: m[0] == 5)
time.sleep(1.5)
send(0x18, {"enabled": True})
send(0x17, {"app": "linmo-xterm"})
msgs = recv(lambda m: m[0] == 4, timeout=15)
windows = [m[1] for m in msgs if m[0] == 2 and m[1]["kind"] == "normal"]
check("X11 window via LAUNCH", bool(windows) and windows[-1]["app"] == "LinmoXterm")
if not windows:
    comp.terminate(); sys.exit(1)
wid = windows[-1]["id"]
check("X11 window id is Wayland-side", wid & 0x80000000 != 0)
check("full frame", any(m[0] == 4 for m in msgs))
msgs += recv(lambda m: m[0] == 8, timeout=3)
icons = [m[1] for m in msgs if m[0] == 8]
check("X11 window icon from WM_CLASS", bool(icons) and struct.unpack_from("<III", icons[-1]) == (wid, 32, 32))

target = os.path.join(work, "typed.txt")
send(0x11, {"id": wid, "x": 30, "y": 30, "button": 1, "pressed": True})
send(0x11, {"id": wid, "x": 30, "y": 30, "button": 1, "pressed": False})
recv(lambda m: False, timeout=0.5)
send(0x19, {"id": wid, "text": f"echo สวัสดี X11 > {target}\n"})
deadline = time.time() + 5
while time.time() < deadline and not (os.path.exists(target) and open(target).read().strip()):
    recv(lambda m: False, timeout=0.2)
check("typing (Thai) into X11 app", os.path.exists(target) and open(target).read().strip() == "สวัสดี X11")

send(0x19, {"id": wid, "text": "printf 'copied in X11 ไทย' | xclip -selection clipboard -i\n"})
msgs = recv(lambda m: m[0] == 0x0B, timeout=6)
check("X11 copy to Mac", [m[1]["text"] for m in msgs if m[0] == 0x0B][-1:] == ["copied in X11 ไทย"])
pasted = os.path.join(work, "pasted.txt")
send(0x1D, {"text": "from Mac สวัสดี"})
recv(lambda m: False, timeout=0.5)
send(0x19, {"id": wid, "text": f"xclip -selection clipboard -o > {pasted}\n"})
deadline = time.time() + 6
while time.time() < deadline and not (os.path.exists(pasted) and open(pasted).read()):
    recv(lambda m: False, timeout=0.2)
check("paste from Mac into X11", os.path.exists(pasted) and open(pasted).read() == "from Mac สวัสดี")

image = os.path.join(work, "image.png")
with open(image, "wb") as f:
    rows = b"".join(b"\0" + os.urandom(60 * 3) for _ in range(60))
    chunk = lambda kind, data: struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 60, 60, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows, 1)) + chunk(b"IEND", b""))
image_bytes = open(image, "rb").read()
pasted_image = os.path.join(work, "pasted.png")
send(0x1D, {"image": base64.b64encode(image_bytes).decode()})
recv(lambda m: False, timeout=0.5)
send(0x19, {"id": wid, "text": f"xclip -selection clipboard -o -t image/png > {pasted_image}\n"})
deadline = time.time() + 6
while time.time() < deadline and not (os.path.exists(pasted_image) and os.path.getsize(pasted_image) == len(image_bytes)):
    recv(lambda m: False, timeout=0.2)
check(f"paste image from Mac into X11 ({len(image_bytes)} bytes)",
      os.path.exists(pasted_image) and open(pasted_image, "rb").read() == image_bytes)

send(0x12, {"id": wid, "keycode": 37, "pressed": True})
send(0x11, {"id": wid, "x": 40, "y": 40, "button": 1, "pressed": True})
msgs = recv(lambda m: m[0] == 2 and m[1]["kind"] == "popup", timeout=4)
popups = [m[1] for m in msgs if m[0] == 2 and m[1]["kind"] == "popup"]
check("X11 menu as popup", bool(popups) and popups[-1]["parent"] == wid)
send(0x11, {"id": wid, "x": 40, "y": 40, "button": 1, "pressed": False})
send(0x12, {"id": wid, "keycode": 37, "pressed": False})
recv(lambda m: m[0] == 3, timeout=3)

send(0x14, {"id": wid, "w": 500, "h": 300})
msgs = recv(lambda m: m[0] == 2 and m[1]["id"] == wid and m[1]["w"] != windows[-1]["w"], timeout=4)
check("resize", any(m[0] == 2 and m[1]["id"] == wid and m[1]["w"] == 500 for m in msgs))
send(0x16, {"id": wid})
check("close", any(m[0] == 3 and m[1]["id"] == wid for m in recv(lambda m: m[0] == 3 and m[1]["id"] == wid, timeout=4)))
comp.terminate()
sys.exit(1 if failures else 0)
