#!/usr/bin/env python3
import base64, json, os, socket, struct, subprocess, sys, tempfile, threading, time, zlib

H = struct.Struct("<IH")
BINARY_KINDS = (4, 7, 8, 9)
binary = os.path.abspath(sys.argv[1])
client_script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "wayland_gtk_client.py")
work = tempfile.mkdtemp(prefix="linmo-test-")
home = os.path.join(work, "home")
runtime = os.path.join(work, "xdg"); os.makedirs(runtime, mode=0o700)


def write_png(path, size):
    row = b"\x00" + b"\xff\x80\x00\xff" * size
    raw = zlib.compress(row * size)
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", raw) + chunk(b"IEND", b""))


apps_dir = os.path.join(home, ".local/share/applications"); os.makedirs(apps_dir)
icon_dir = os.path.join(home, ".local/share/icons/hicolor/48x48/apps"); os.makedirs(icon_dir)
with open(os.path.join(apps_dir, "linmotest.desktop"), "w") as f:
    f.write("[Desktop Entry]\nType=Application\nName=LinMO Test\nExec=true\nIcon=linmo-test-icon\n")
write_png(os.path.join(icon_dir, "linmo-test-icon.png"), 48)
svg_dir = os.path.join(home, ".local/share/icons/hicolor/scalable/apps"); os.makedirs(svg_dir)
with open(os.path.join(apps_dir, "linmosvg.desktop"), "w") as f:
    f.write("[Desktop Entry]\nType=Application\nName=LinMO SVG\nExec=true\nIcon=linmo-svg-icon\n")
with open(os.path.join(svg_dir, "linmo-svg-icon.svg"), "w") as f:
    f.write('<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48"><rect width="48" height="48" fill="#ff8000"/></svg>')

sock_path = os.path.join(work, "mac.sock")
srv = socket.socket(socket.AF_UNIX); srv.bind(sock_path); srv.listen(1)
env = dict(os.environ, XDG_RUNTIME_DIR=runtime, LINMO_AGENT_UNIX=sock_path, HOME=home)
env.pop("DISPLAY", None)
comp = subprocess.Popen([binary], env=env)
srv.settimeout(10); conn, _ = srv.accept(); conn.settimeout(0.2)
buf = bytearray(); failures = []
text_inputs = []


def recv(pred, timeout=8):
    global buf
    end, out = time.time() + timeout, []
    while time.time() < end:
        while len(buf) >= 6:
            n, k = H.unpack_from(buf)
            if len(buf) < 6 + n: break
            p = bytes(buf[6:6 + n]); del buf[:6 + n]
            m = (k, p if k in BINARY_KINDS else json.loads(p)); out.append(m)
            if k == 0x0C: text_inputs.append(m[1])
            if pred(m): return out
        try: data = conn.recv(1 << 20)
        except socket.timeout: continue
        if not data: break
        buf += data
    return out


def send(k, o):
    p = o if isinstance(o, bytes) else json.dumps(o).encode()
    conn.sendall(H.pack(len(p), k) + p)


def click(wid, x, y, button=1):
    for pressed in (True, False):
        send(0x11, {"id": wid, "x": x, "y": y, "button": button, "pressed": pressed})


def key(code):
    for pressed in (True, False):
        send(0x12, {"id": 0, "keycode": code, "pressed": pressed})


def check(name, ok):
    print(("PASS " if ok else "FAIL ") + name, flush=True)
    if not ok: failures.append(name)


lines, lines_lock = [], threading.Lock()


def wait_line(prefix, timeout=5):
    end = time.time() + timeout
    while time.time() < end:
        with lines_lock:
            for line in lines:
                if line.startswith(prefix):
                    lines.remove(line)
                    return line[len(prefix):].strip()
        recv(lambda m: False, timeout=0.1)
    return None


msgs = recv(lambda m: m[0] == 5)
hello = next((m[1] for m in msgs if m[0] == 1), {})
check("hello features", {"clipboard", "clipboard-image", "drop", "dragout", "icons", "popupclose", "preedit"} <= set(hello.get("features", [])))
apps = {a["id"]: a for m in msgs if m[0] == 5 for a in m[1]["apps"]}
svg_app = apps.get("linmosvg", {})
svg_png = base64.b64decode(svg_app.get("icon", "")) if svg_app.get("icon") else b""
check("SVG app icon → PNG in app list", svg_app.get("iconFormat") == "png" and svg_png.startswith(b"\x89PNG")
      and struct.unpack(">II", svg_png[16:24]) == (128, 128))

cenv = dict(env, WAYLAND_DISPLAY="linmo-0", GDK_BACKEND="wayland", LANG="C.UTF-8", NO_AT_BRIDGE="1")
app = subprocess.Popen([sys.executable, client_script], env=cenv, stdin=subprocess.PIPE,
                       stdout=subprocess.PIPE, text=True, bufsize=1)
threading.Thread(target=lambda: [lines.append(l) for l in app.stdout], daemon=True).start()
send(0x18, {"enabled": True})

msgs = recv(lambda m: m[0] == 8, timeout=10)
windows = [m[1] for m in msgs if m[0] == 2 and m[1]["kind"] == "normal"]
check("window", bool(windows))
if not windows:
    app.kill(); comp.terminate(); sys.exit(1)
wid = windows[-1]["id"]
check("app_id", windows[-1]["app"] == "linmotest")
icons = [m[1] for m in msgs if m[0] == 8]
icon_ok = False
if icons:
    iid, iw, ih = struct.unpack_from("<III", icons[-1])
    b, g, r, a = icons[-1][12:16]
    icon_ok = (iid, iw, ih) == (wid, 48, 48) and (b, g, r, a) == (0x00, 0x80, 0xff, 0xff)
check("window icon from .desktop", icon_ok)
wait_line("READY")

click(wid, 40, 40)
recv(lambda m: False, timeout=0.5)
send(0x1D, {"text": "สวัสดีจาก Mac"})
recv(lambda m: False, timeout=0.3)
app.stdin.write("paste\n"); app.stdin.flush()
check("paste from Mac", wait_line("PASTE") == "สวัสดีจาก Mac")

app.stdin.write("copy hello from linux ภาษาไทย\n"); app.stdin.flush()
msgs = recv(lambda m: m[0] == 0x0B, timeout=5)
copied = [m[1].get("text") for m in msgs if m[0] == 0x0B]
check("copy to Mac", copied[-1:] == ["hello from linux ภาษาไทย"])

image_path = os.path.join(work, "copy.png")
write_png(image_path, 20)
app.stdin.write(f"copyimage {image_path}\n"); app.stdin.flush()
msgs = recv(lambda m: m[0] == 0x0B, timeout=5)
images = [base64.b64decode(m[1]["image"]) for m in msgs if m[0] == 0x0B and "image" in m[1]]
check("copy image to Mac", bool(images) and images[-1].startswith(b"\x89PNG")
      and struct.unpack(">II", images[-1][16:24]) == (20, 20))

write_png(image_path, 30)
send(0x1D, {"image": base64.b64encode(open(image_path, "rb").read()).decode()})
recv(lambda m: False, timeout=0.3)
app.stdin.write("pasteimage\n"); app.stdin.flush()
check("paste image from Mac", wait_line("PASTEIMAGE") == "30 30 ff8000")

click(wid, 60, 60, button=3)
msgs = recv(lambda m: m[0] == 2 and m[1]["kind"] == "popup", timeout=5)
popups = [m[1] for m in msgs if m[0] == 2 and m[1]["kind"] == "popup"]
check("menu opens", bool(popups))
recv(lambda m: False, timeout=0.5)
key(116)
key(36)
check("menu keyboard (popup grab)", wait_line("MENU") == "first")
recv(lambda m: m[0] == 3, timeout=3)

click(wid, 60, 60, button=3)
msgs = recv(lambda m: m[0] == 2 and m[1]["kind"] == "popup", timeout=5)
popups = [m[1] for m in msgs if m[0] == 2 and m[1]["kind"] == "popup"]
closed = []
if popups:
    pid = popups[-1]["id"]
    recv(lambda m: False, timeout=0.3)
    send(0x16, {"id": pid})
    closed = [m for m in recv(lambda m: m[0] == 3 and m[1]["id"] == pid, timeout=3) if m[0] == 3 and m[1]["id"] == pid]
check("menu closes on CLOSE", bool(closed))
check("no item chosen when menu closed", wait_line("MENU", timeout=0.5) is None)

out_path = os.path.join(work, "ลากออก.txt")
with open(out_path, "wb") as f: f.write("ข้อมูลที่ลากออก\n".encode())
app.stdin.write(f"drag {out_path}\n"); app.stdin.flush()
click(wid, 100, 100)
recv(lambda m: False, timeout=0.3)
send(0x11, {"id": wid, "x": 100, "y": 100, "button": 1, "pressed": True})
for step in range(1, 8):
    send(0x10, {"id": wid, "x": 100 + step * 6, "y": 100})
    recv(lambda m: False, timeout=0.05)
began = wait_line("DRAG_BEGIN", timeout=3) is not None
check("drag starts in app", began)
send(0x1C, {"id": wid})
msgs = recv(lambda m: m[0] in (9, 10), timeout=5)
data = [m[1] for m in msgs if m[0] == 9]
files_ok = False
if data:
    (jlen,) = struct.unpack_from("<I", data[-1])
    meta = json.loads(data[-1][4:4 + jlen])
    body = data[-1][4 + jlen:]
    files_ok = meta["files"] == [{"name": "ลากออก.txt", "size": os.path.getsize(out_path)}] and body == open(out_path, "rb").read()
check("drag out to Mac", files_ok)
check("drag cancelled in Linux", wait_line("DRAG_END", timeout=3) is not None and wait_line("DROP", timeout=0.5) is None)
send(0x11, {"id": wid, "x": 140, "y": 100, "button": 1, "pressed": False})

content = "ไฟล์ทดสอบ\n".encode()
meta = json.dumps({"id": wid, "x": 80, "y": 80, "files": [{"name": "ทดสอบ วาง.txt", "size": len(content)}]}).encode()
send(0x1A, struct.pack("<I", len(meta)) + meta + content)
dropped = wait_line("DROP", timeout=5) or ""
saved = os.path.join(home, "Downloads", "LinMO", "ทดสอบ วาง.txt")
from urllib.parse import unquote
check("drop file", dropped.startswith("file://") and unquote(dropped[len("file://"):]) == saved
      and os.path.exists(saved) and open(saved, "rb").read() == content)

send(0x1C, {"id": wid})
msgs = recv(lambda m: m[0] in (9, 10), timeout=3)
check("no drag → DRAG_NONE", any(m[0] == 10 for m in msgs) and not any(m[0] == 9 for m in msgs))

click(wid, 40, windows[-1]["h"] - 15)
recv(lambda m: False, timeout=0.5)
check("text input enabled + cursor", bool(text_inputs) and text_inputs[-1]["enabled"]
      and text_inputs[-1]["id"] == wid and text_inputs[-1]["h"] > 0)
send(0x1E, {"id": wid, "text": "にほん", "cursor": 3})
check("preedit shown in app", wait_line("PREEDIT") == "にほん")
send(0x19, {"id": wid, "text": "日本語\n"})
activated = wait_line("ACTIVATE")
check("commit text + Enter", activated == "日本語")

svg_client = subprocess.Popen([sys.executable, client_script], env=dict(cenv, LINMO_TEST_APP_ID="linmosvg"),
                              stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, text=True)
msgs = recv(lambda m: m[0] == 8, timeout=10)
icons = [m[1] for m in msgs if m[0] == 8]
svg_icon_ok = False
if icons:
    _, iw, ih = struct.unpack_from("<III", icons[-1])
    svg_icon_ok = (iw, ih) == (128, 128) and tuple(icons[-1][12:16]) == (0x00, 0x80, 0xff, 0xff)
check("window icon from SVG", svg_icon_ok)
svg_client.kill()

app.kill(); comp.terminate()
sys.exit(1 if failures else 0)
