#!/usr/bin/env python3
import base64, json, os, socket, struct, subprocess, sys, tempfile, time, zlib

H = struct.Struct("<IH")
agent = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "linmo-agent.py")
work = tempfile.mkdtemp(prefix="linmo-test-")
sock_path = os.path.join(work, "mac.sock")
srv = socket.socket(socket.AF_UNIX); srv.bind(sock_path); srv.listen(1)
xvfb = subprocess.Popen(["Xvfb", ":77", "-screen", "0", "1024x768x24"], stderr=subprocess.DEVNULL)
time.sleep(1)
env = dict(os.environ, DISPLAY=":77", LINMO_AGENT_UNIX=sock_path, HOME=work)
agent_log = open(os.path.join(work, "agent.log"), "w")
proc = subprocess.Popen([sys.executable, agent], env=env, stderr=agent_log)
srv.settimeout(10); conn, _ = srv.accept(); conn.settimeout(0.2)
buf = bytearray(); failures = []


def recv(pred, timeout=5):
    global buf
    end, out = time.time() + timeout, []
    while time.time() < end:
        while len(buf) >= 6:
            n, k = H.unpack_from(buf)
            if len(buf) < 6 + n: break
            p = bytes(buf[6:6 + n]); del buf[:6 + n]
            m = (k, p if k in (4, 7, 8, 9) else json.loads(p)); out.append(m)
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


msgs = recv(lambda m: m[0] == 1)
hello = next((m[1] for m in msgs if m[0] == 1), {})
check("hello: version 8 + clipboard + clipboard-image + folders",
      hello.get("version") == 8 and {"clipboard", "clipboard-image", "folders"} <= set(hello.get("features", [])))

xenv = dict(os.environ, DISPLAY=":77")
for text in ("copied in X11 ภาษาไทย", "second copy"):
    subprocess.run(["xclip", "-selection", "clipboard", "-i"], input=text.encode(), env=xenv)
    msgs = recv(lambda m: m[0] == 0x0B, timeout=4)
    check(f"X11 copy → Mac ({text})", [m[1]["text"] for m in msgs if m[0] == 0x0B][-1:] == [text])

send(0x1D, {"text": "from Mac สวัสดี"})
time.sleep(0.5)
out = subprocess.run(["xclip", "-selection", "clipboard", "-o"], capture_output=True, env=xenv, timeout=5).stdout
check("Mac → X11 paste (UTF8_STRING)", out.decode() == "from Mac สวัสดี")
targets = subprocess.run(["xclip", "-selection", "clipboard", "-o", "-t", "TARGETS"], capture_output=True, env=xenv, timeout=5).stdout.decode()
check("TARGETS", "UTF8_STRING" in targets and "STRING" in targets)
check("no echo back to Mac", not any(m[0] == 0x0B for m in recv(lambda m: False, timeout=1)))


def png(width, height, noisy=False):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    rows = b"".join(b"\0" + (os.urandom(width * 3) if noisy else bytes([200, 30, 30]) * width) for _ in range(height))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows, 1)) + chunk(b"IEND", b""))


for label, image in (("small", png(16, 16)), ("INCR", png(400, 400, noisy=True))):
    path = os.path.join(work, "copy.png")
    with open(path, "wb") as f:
        f.write(image)
    subprocess.run(["xclip", "-selection", "clipboard", "-t", "image/png", "-i", path], env=xenv)
    msgs = recv(lambda m: m[0] == 0x0B, timeout=8)
    got = [m[1] for m in msgs if m[0] == 0x0B][-1:]
    check(f"X11 copy image → Mac ({label}, {len(image)} bytes)",
          bool(got) and base64.b64decode(got[0].get("image", "")) == image and "text" not in got[0])

long_text = ("ข้อความยาว LinMO " * 40000)[:200000]
subprocess.run(["xclip", "-selection", "clipboard", "-i"], input=long_text.encode(), env=xenv)
msgs = recv(lambda m: m[0] == 0x0B, timeout=8)
check(f"X11 copy long text → Mac ({len(long_text.encode())} bytes)", [m[1].get("text") for m in msgs if m[0] == 0x0B][-1:] == [long_text])

for label, image in (("small", png(8, 8)), ("INCR", png(500, 500, noisy=True))):
    send(0x1D, {"image": base64.b64encode(image).decode()})
    time.sleep(0.5)
    targets = subprocess.run(["xclip", "-selection", "clipboard", "-o", "-t", "TARGETS"], capture_output=True, env=xenv, timeout=5).stdout.decode()
    out = subprocess.run(["xclip", "-selection", "clipboard", "-o", "-t", "image/png"], capture_output=True, env=xenv, timeout=10).stdout
    check(f"Mac image → X11 paste ({label}, {len(image)} bytes)", out == image and "image/png" in targets and "UTF8_STRING" not in targets)

send(0x1D, {"text": long_text})
time.sleep(0.5)
out = subprocess.run(["xclip", "-selection", "clipboard", "-o"], capture_output=True, env=xenv, timeout=10).stdout
check("Mac long text → X11 paste (INCR)", out.decode() == long_text)

image = png(4, 4)
send(0x1D, {"text": "both", "image": base64.b64encode(image).decode()})
time.sleep(0.5)
out_text = subprocess.run(["xclip", "-selection", "clipboard", "-o"], capture_output=True, env=xenv, timeout=5).stdout
out_png = subprocess.run(["xclip", "-selection", "clipboard", "-o", "-t", "image/png"], capture_output=True, env=xenv, timeout=5).stdout
check("Mac text + image → X11 paste both", out_text == b"both" and out_png == image)

proc.terminate(); xvfb.terminate()
if failures:
    print(open(agent_log.name).read()[-3000:])
sys.exit(1 if failures else 0)
