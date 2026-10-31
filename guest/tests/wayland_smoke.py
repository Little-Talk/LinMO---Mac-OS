#!/usr/bin/env python3
import json, os, socket, struct, subprocess, sys, tempfile, time

H = struct.Struct("<IH")
binary = os.path.abspath(sys.argv[1])
work = tempfile.mkdtemp(prefix="linmo-test-")
runtime = os.path.join(work, "xdg"); os.makedirs(runtime, mode=0o700)
sock_path = os.path.join(work, "mac.sock")
srv = socket.socket(socket.AF_UNIX); srv.bind(sock_path); srv.listen(1)
env = dict(os.environ, XDG_RUNTIME_DIR=runtime, LINMO_AGENT_UNIX=sock_path); env.pop("DISPLAY", None)
comp = subprocess.Popen([binary], env=env)
srv.settimeout(10); conn, _ = srv.accept(); conn.settimeout(5)
buf = bytearray(); failures = []

def recv(pred, timeout=8):
    global buf
    end, out = time.time() + timeout, []
    while time.time() < end:
        while len(buf) >= 6:
            n, k = H.unpack_from(buf)
            if len(buf) < 6 + n: break
            p = bytes(buf[6:6 + n]); del buf[:6 + n]
            m = (k, p if k in (4, 7, 8) else json.loads(p)); out.append(m)
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

msgs = recv(lambda m: m[0] == 5)
check("hello", any(m[0] == 1 and "wayland" in m[1]["features"] for m in msgs))
cenv = dict(env, WAYLAND_DISPLAY="linmo-0", LANG="C.UTF-8")
target = os.path.join(work, "typed.txt")
foot = subprocess.Popen(["foot", "sh"], env=cenv, stderr=subprocess.DEVNULL)
msgs = recv(lambda m: m[0] == 2, timeout=10)
windows = [m[1] for m in msgs if m[0] == 2]
check("window", bool(windows))
if windows:
    wid = windows[-1]["id"]
    send(0x18, {"enabled": True})
    check("full frame", any(m[0] == 4 for m in recv(lambda m: m[0] == 4)))
    send(0x11, {"id": wid, "x": 20, "y": 20, "button": 1, "pressed": True})
    send(0x11, {"id": wid, "x": 20, "y": 20, "button": 1, "pressed": False})
    time.sleep(0.5); recv(lambda m: False, timeout=0.5)
    send(0x19, {"id": wid, "text": f"echo สวัสดี ok > {target}\n"})
    msgs = recv(lambda m: False, timeout=2.5)
    check("partial frames", any(m[0] == 7 for m in msgs))
    check("thai typing", os.path.exists(target) and open(target).read().strip() == "สวัสดี ok")
    check("idle sends nothing", not any(m[0] in (4, 7) for m in recv(lambda m: False, timeout=1.5)))
    send(0x14, {"id": wid, "w": 500, "h": 300})
    check("resize", any(m[0] == 2 and m[1]["w"] != windows[-1]["w"] for m in recv(lambda m: m[0] == 2, timeout=3)))
    send(0x16, {"id": wid})
    check("close", any(m[0] == 3 for m in recv(lambda m: m[0] == 3, timeout=3)))
foot.kill(); comp.terminate()
sys.exit(1 if failures else 0)
