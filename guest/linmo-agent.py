#!/usr/bin/env python3

import base64
import configparser
import glob
import json
import os
import select
import shutil
import socket
import struct
import subprocess
import sys
import time
import zlib

from Xlib import X, Xatom, Xutil, display, error
from Xlib.ext import composite, xtest
from Xlib.protocol import event as xevent

try:
    from Xlib.ext import damage as xdamage
except ImportError:
    xdamage = None

try:
    from Xlib.ext import xfixes
except ImportError:
    xfixes = None

VERSION = 8
FEATURES = ["damage", "icons", "text", "drop", "scale", "shm", "dragout", "folders"]
HOST_CID = 2
PORT = int(os.environ.get("LINMO_AGENT_PORT", "5200"))

MSG_HELLO = 0x01
MSG_WINDOW = 0x02
MSG_WINDOW_CLOSED = 0x03
MSG_FRAME = 0x04
MSG_APPS = 0x05
MSG_FOCUSED = 0x06
MSG_FRAME_RECT = 0x07
MSG_ICON = 0x08
MSG_DRAG_DATA = 0x09
MSG_DRAG_NONE = 0x0A
MSG_CLIPBOARD = 0x0B
MSG_POINTER = 0x10
MSG_BUTTON = 0x11
MSG_KEY = 0x12
MSG_SCROLL = 0x13
MSG_RESIZE = 0x14
MSG_FOCUS = 0x15
MSG_CLOSE = 0x16
MSG_LAUNCH = 0x17
MSG_STREAM = 0x18
MSG_TEXT = 0x19
MSG_DROP = 0x1A
MSG_CONFIG = 0x1B
MSG_DRAG_OUT = 0x1C
MSG_SET_CLIPBOARD = 0x1D
MSG_FOLDER_CHANGED = 0x20

FRAME_INTERVAL = 1 / 30
SCAN_INTERVAL = 0.25
FULL_FRAME_RATIO = 0.6
HEADER = struct.Struct("<IH")
KEYSYM_RETURN, KEYSYM_TAB, KEYSYM_ESCAPE = 0xFF0D, 0xFF09, 0xFF1B


def log(*args):
    print("[linmo-agent]", *args, file=sys.stderr, flush=True)



class Channel:

    def __init__(self, sock):
        self.sock = sock
        self.sock.setblocking(False)
        self.inbox = bytearray()
        self.outbox = bytearray()

    def fileno(self):
        return self.sock.fileno()

    def send(self, kind, payload):
        if isinstance(payload, (dict, list)):
            payload = json.dumps(payload, ensure_ascii=False).encode()
        self.outbox += HEADER.pack(len(payload), kind) + payload
        self.flush()

    def flush(self):
        while self.outbox:
            try:
                sent = self.sock.send(self.outbox)
            except BlockingIOError:
                return
            del self.outbox[:sent]

    @property
    def backlogged(self):
        return len(self.outbox) > 16 * 1024 * 1024

    def receive(self):
        try:
            data = self.sock.recv(1 << 20)
        except BlockingIOError:
            return []
        if not data:
            raise EOFError
        self.inbox += data
        messages = []
        while len(self.inbox) >= HEADER.size:
            length, kind = HEADER.unpack_from(self.inbox)
            if len(self.inbox) < HEADER.size + length:
                break
            payload = bytes(self.inbox[HEADER.size:HEADER.size + length])
            del self.inbox[:HEADER.size + length]
            if kind == MSG_DROP:
                messages.append((kind, payload))
                continue
            try:
                messages.append((kind, json.loads(payload) if payload else {}))
            except ValueError:
                pass
        return messages

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


def connect():
    family = getattr(socket, "AF_VSOCK", None)
    target = (HOST_CID, PORT)
    if os.environ.get("LINMO_AGENT_UNIX"):
        family, target = socket.AF_UNIX, os.environ["LINMO_AGENT_UNIX"]
    if family is None:
        return None
    try:
        sock = socket.socket(family, socket.SOCK_STREAM)
        sock.settimeout(3)
        sock.connect(target)
        return Channel(sock)
    except OSError:
        return None



import ctypes
import ctypes.util

ZPIXMAP = 2
IPC_PRIVATE = 0
IPC_CREAT = 0o1000
IPC_RMID = 0
ALL_PLANES = 0xFFFFFFFF


class XImage(ctypes.Structure):
    _fields_ = [
        ("width", ctypes.c_int),
        ("height", ctypes.c_int),
        ("xoffset", ctypes.c_int),
        ("format", ctypes.c_int),
        ("data", ctypes.c_void_p),
        ("byte_order", ctypes.c_int),
        ("bitmap_unit", ctypes.c_int),
        ("bitmap_bit_order", ctypes.c_int),
        ("bitmap_pad", ctypes.c_int),
        ("depth", ctypes.c_int),
        ("bytes_per_line", ctypes.c_int),
        ("bits_per_pixel", ctypes.c_int),
    ]


class XShmSegmentInfo(ctypes.Structure):
    _fields_ = [
        ("shmseg", ctypes.c_ulong),
        ("shmid", ctypes.c_int),
        ("shmaddr", ctypes.c_void_p),
        ("readOnly", ctypes.c_int),
    ]


class XWindowAttributes(ctypes.Structure):
    _fields_ = [
        ("x", ctypes.c_int), ("y", ctypes.c_int),
        ("width", ctypes.c_int), ("height", ctypes.c_int),
        ("border_width", ctypes.c_int), ("depth", ctypes.c_int),
        ("visual", ctypes.c_void_p), ("root", ctypes.c_ulong),
        ("class_", ctypes.c_int), ("bit_gravity", ctypes.c_int), ("win_gravity", ctypes.c_int),
        ("backing_store", ctypes.c_int), ("backing_planes", ctypes.c_ulong),
        ("backing_pixel", ctypes.c_ulong), ("save_under", ctypes.c_int),
        ("colormap", ctypes.c_ulong), ("map_installed", ctypes.c_int), ("map_state", ctypes.c_int),
        ("all_event_masks", ctypes.c_long), ("your_event_mask", ctypes.c_long),
        ("do_not_propagate_mask", ctypes.c_long), ("override_redirect", ctypes.c_int),
        ("screen", ctypes.c_void_p),
    ]


ERROR_HANDLER = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p)


class _Segment:
    def __init__(self, owner, visual, depth, width, height):
        self.owner = owner
        x11, xext, libc = owner.x11, owner.xext, owner.libc
        self.info = XShmSegmentInfo()
        self.image = xext.XShmCreateImage(owner.dpy, visual, depth, ZPIXMAP, None,
                                          ctypes.byref(self.info), width, height)
        if not self.image:
            raise OSError("XShmCreateImage failed")
        img = self.image.contents
        self.size = img.bytes_per_line * img.height
        self.info.shmid = libc.shmget(IPC_PRIVATE, self.size, IPC_CREAT | 0o600)
        if self.info.shmid < 0:
            x11.XDestroyImage(self.image)
            raise OSError("shmget failed")
        addr = libc.shmat(self.info.shmid, None, 0)
        if addr in (None, ctypes.c_void_p(-1).value):
            libc.shmctl(self.info.shmid, IPC_RMID, None)
            x11.XDestroyImage(self.image)
            raise OSError("shmat failed")
        self.info.shmaddr = addr
        self.info.readOnly = 0
        img.data = addr
        if not xext.XShmAttach(owner.dpy, ctypes.byref(self.info)):
            raise OSError("XShmAttach failed")
        x11.XSync(owner.dpy, 0)
        libc.shmctl(self.info.shmid, IPC_RMID, None)

    def destroy(self):
        o = self.owner
        o.xext.XShmDetach(o.dpy, ctypes.byref(self.info))
        o.x11.XSync(o.dpy, 0)
        self.image.contents.data = None
        o.x11.XDestroyImage(self.image)
        o.libc.shmdt(ctypes.c_void_p(self.info.shmaddr))


class ShmCapture:

    MAX_SEGMENTS = 8

    def __init__(self):
        x11_name, xext_name = ctypes.util.find_library("X11"), ctypes.util.find_library("Xext")
        if not x11_name or not xext_name:
            raise OSError("libX11/libXext not found")
        self.x11 = ctypes.CDLL(x11_name)
        self.xext = ctypes.CDLL(xext_name)
        self.libc = ctypes.CDLL(None, use_errno=True)

        self.x11.XOpenDisplay.restype = ctypes.c_void_p
        self.x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
        self.x11.XSync.argtypes = [ctypes.c_void_p, ctypes.c_int]
        self.x11.XDestroyImage.argtypes = [ctypes.POINTER(XImage)]
        self.x11.XGetWindowAttributes.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(XWindowAttributes)]
        self.x11.XSetErrorHandler.restype = ctypes.c_void_p
        self.x11.XSetErrorHandler.argtypes = [ERROR_HANDLER]
        self.xext.XShmQueryExtension.argtypes = [ctypes.c_void_p]
        self.xext.XShmCreateImage.restype = ctypes.POINTER(XImage)
        self.xext.XShmCreateImage.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint, ctypes.c_int,
                                              ctypes.c_char_p, ctypes.POINTER(XShmSegmentInfo),
                                              ctypes.c_uint, ctypes.c_uint]
        self.xext.XShmAttach.argtypes = [ctypes.c_void_p, ctypes.POINTER(XShmSegmentInfo)]
        self.xext.XShmDetach.argtypes = [ctypes.c_void_p, ctypes.POINTER(XShmSegmentInfo)]
        self.xext.XShmGetImage.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(XImage),
                                           ctypes.c_int, ctypes.c_int, ctypes.c_ulong]
        self.libc.shmget.argtypes = [ctypes.c_int, ctypes.c_size_t, ctypes.c_int]
        self.libc.shmat.restype = ctypes.c_void_p
        self.libc.shmat.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_int]
        self.libc.shmdt.argtypes = [ctypes.c_void_p]
        self.libc.shmctl.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]

        self.dpy = self.x11.XOpenDisplay(None)
        if not self.dpy:
            raise OSError("cannot open display")
        if not self.xext.XShmQueryExtension(self.dpy):
            raise OSError("MIT-SHM not available")

        self.failed = False

        def on_error(_display, _event):
            self.failed = True
            return 0

        self._handler = ERROR_HANDLER(on_error)
        self.x11.XSetErrorHandler(self._handler)
        self.segments = {}

    def _segment(self, visual, depth, width, height):
        key = (visual, depth, width, height)
        seg = self.segments.pop(key, None)
        if seg is None:
            if len(self.segments) >= self.MAX_SEGMENTS:
                old_key = next(iter(self.segments))
                self.segments.pop(old_key).destroy()
            seg = _Segment(self, visual, depth, width, height)
        self.segments[key] = seg
        return seg

    def capture(self, window_id, x, y, width, height):
        attrs = XWindowAttributes()
        self.failed = False
        if not self.x11.XGetWindowAttributes(self.dpy, window_id, ctypes.byref(attrs)) or self.failed:
            return None
        if attrs.depth not in (24, 32):
            return None
        try:
            seg = self._segment(attrs.visual, attrs.depth, width, height)
        except OSError:
            return None
        self.failed = False
        ok = self.xext.XShmGetImage(self.dpy, window_id, seg.image, x, y, ALL_PLANES)
        self.x11.XSync(self.dpy, 0)
        if not ok or self.failed:
            return None
        img = seg.image.contents
        if img.bits_per_pixel != 32:
            return None
        stride = img.bytes_per_line
        raw = ctypes.string_at(seg.info.shmaddr, stride * height)
        if stride == width * 4:
            return raw
        return b"".join(raw[r * stride:r * stride + width * 4] for r in range(height))

    def close(self):
        for seg in self.segments.values():
            seg.destroy()
        self.segments.clear()



class Desktop:
    def __init__(self):
        self.d = display.Display()
        self.screen = self.d.screen()
        self.root = self.screen.root
        self.atoms = {}
        self.d.set_error_handler(lambda *args: None)

        try:
            self.d.composite_query_version()
            self.root.composite_redirect_subwindows(composite.RedirectAutomatic)
            self.d.sync()
        except Exception as exc:
            log("composite unavailable:", exc)

        self.damage_event = None
        if xdamage is not None and self.d.has_extension("DAMAGE"):
            try:
                self.d.damage_query_version()
                self.damage_event = self.d.extension_event.DamageNotify
            except Exception as exc:
                log("damage unavailable:", exc)

        self.shm = None
        try:
            self.shm = ShmCapture()
        except (OSError, AttributeError) as exc:
            log("MIT-SHM unavailable:", exc)

        self.helper = self.root.create_window(-10, -10, 1, 1, 0, X.CopyFromParent, X.InputOutput,
                                              X.CopyFromParent, override_redirect=True,
                                              event_mask=X.PropertyChangeMask)
        self.catcher = self.root.create_window(0, 0, 24, 24, 0, X.CopyFromParent, X.InputOutput,
                                               X.CopyFromParent, override_redirect=True,
                                               event_mask=X.PropertyChangeMask)
        self.catcher.change_property(self.atom("XdndAware"), Xatom.ATOM, 32, [5])
        self.keyboard = Keyboard(self)
        self.clipboard = Clipboard(self)

    def atom(self, name):
        if name not in self.atoms:
            self.atoms[name] = self.d.intern_atom(name)
        return self.atoms[name]

    def window(self, wid):
        return self.d.create_resource_object("window", wid)

    @property
    def screen_size(self):
        geo = self.root.get_geometry()
        return geo.width, geo.height

    def _prop(self, win, name, kind=X.AnyPropertyType):
        try:
            value = win.get_full_property(self.atom(name), kind)
        except error.XError:
            return None
        return value.value if value else None

    def client_list(self):
        value = self._prop(self.root, "_NET_CLIENT_LIST", Xatom.WINDOW)
        return list(value) if value is not None else []

    def active_window(self):
        value = self._prop(self.root, "_NET_ACTIVE_WINDOW", Xatom.WINDOW)
        return int(value[0]) if value is not None and len(value) else 0

    def title(self, win):
        value = self._prop(win, "_NET_WM_NAME", self.atom("UTF8_STRING"))
        if value:
            return value.decode("utf-8", "replace") if isinstance(value, bytes) else str(value)
        try:
            name = win.get_wm_name()
            return name.decode("latin-1") if isinstance(name, bytes) else (name or "")
        except error.XError:
            return ""

    def app_id(self, win):
        try:
            cls = win.get_wm_class()
            return cls[1] if cls else ""
        except error.XError:
            return ""

    def is_regular(self, win):
        types = self._prop(win, "_NET_WM_WINDOW_TYPE", Xatom.ATOM)
        if types is not None:
            blocked = {self.atom("_NET_WM_WINDOW_TYPE_DESKTOP"), self.atom("_NET_WM_WINDOW_TYPE_DOCK")}
            if any(t in blocked for t in types):
                return False
        state = self._prop(win, "_NET_WM_STATE", Xatom.ATOM)
        if state is not None and self.atom("_NET_WM_STATE_HIDDEN") in state:
            return False
        return True

    def transient_for(self, win):
        try:
            parent = win.get_wm_transient_for()
            return parent.id if parent else 0
        except error.XError:
            return 0

    def raw_geometry(self, win):
        try:
            geo = win.get_geometry()
            pos = win.translate_coords(self.root, 0, 0)
            return -pos.x, -pos.y, geo.width, geo.height
        except error.XError:
            return None

    def insets(self, win):
        value = self._prop(win, "_GTK_FRAME_EXTENTS", Xatom.CARDINAL)
        if value is not None and len(value) >= 4:
            return tuple(max(0, int(v)) for v in value[:4])
        return 0, 0, 0, 0

    def geometry(self, win):
        geo = self.raw_geometry(win)
        if not geo:
            return None
        x, y, w, h = geo
        left, right, top, bottom = self.insets(win)
        if w - left - right < 1 or h - top - bottom < 1:
            return geo
        return x + left, y + top, w - left - right, h - top - bottom

    def min_size(self, win):
        try:
            hints = win.get_wm_normal_hints()
        except error.XError:
            return 0, 0
        if not hints or not (hints.flags & Xutil.PMinSize):
            return 0, 0
        left, right, top, bottom = self.insets(win)
        return max(0, hints.min_width - left - right), max(0, hints.min_height - top - bottom)

    def popups(self):
        result = []
        try:
            children = self.root.query_tree().children
        except error.XError:
            return result
        sw, sh = self.screen_size
        for win in children:
            if win.id in (self.helper.id, self.catcher.id):
                continue
            try:
                attrs = win.get_attributes()
            except error.XError:
                continue
            if not attrs.override_redirect or attrs.map_state != X.IsViewable:
                continue
            geo = self.geometry(win)
            if not geo:
                continue
            x, y, w, h = geo
            if w <= 2 or h <= 2 or (w >= sw and h >= sh):
                continue
            result.append((win, geo))
        return result

    def capture(self, win, x, y, w, h):
        if self.shm is not None:
            pixels = self.shm.capture(win.id, x, y, w, h)
            if pixels is not None:
                return pixels
        try:
            image = win.get_image(x, y, w, h, X.ZPixmap, 0xFFFFFFFF)
        except (error.XError, struct.error):
            return None
        data = image.data
        if isinstance(data, str):
            data = data.encode("latin-1")
        if len(data) != w * h * 4:
            return None
        return data

    def icon(self, win, target=64):
        data = self._prop(win, "_NET_WM_ICON", Xatom.CARDINAL)
        if data is None or len(data) < 3:
            return None
        icons, i = [], 0
        data = list(data)
        while i + 2 <= len(data):
            w, h = data[i], data[i + 1]
            if w <= 0 or h <= 0 or i + 2 + w * h > len(data):
                break
            icons.append((w, h, i + 2))
            i += 2 + w * h
        if not icons:
            return None
        bigger = [c for c in icons if c[0] >= target]
        w, h, start = min(bigger, key=lambda c: c[0]) if bigger else max(icons, key=lambda c: c[0])
        if w > 256:
            return None
        out = bytearray(w * h * 4)
        for n, argb in enumerate(data[start:start + w * h]):
            a = (argb >> 24) & 0xFF
            r = ((argb >> 16) & 0xFF) * a // 255
            g = ((argb >> 8) & 0xFF) * a // 255
            b = (argb & 0xFF) * a // 255
            out[n * 4:n * 4 + 4] = bytes((b, g, r, a))
        return w, h, bytes(out)


    def client_message(self, win, atom_name, data, target=None, mask=None):
        ev = xevent.ClientMessage(window=win, client_type=self.atom(atom_name), data=(32, data))
        if target is None:
            self.root.send_event(ev, event_mask=X.SubstructureRedirectMask | X.SubstructureNotifyMask)
        else:
            target.send_event(ev, event_mask=mask or 0)
        self.d.flush()

    def activate(self, wid):
        win = self.window(wid)
        self.client_message(win, "_NET_ACTIVE_WINDOW", [2, X.CurrentTime, 0, 0, 0])
        try:
            win.raise_window()
            self.d.sync()
        except error.XError:
            pass

    def ensure_on_screen(self, wid):
        win = self.window(wid)
        geo = self.geometry(win)
        if not geo:
            return
        x, y, w, h = geo
        sw, sh = self.screen_size
        nx = min(max(x, 0), max(sw - w, 0))
        ny = min(max(y, 0), max(sh - h, 0))
        if (nx, ny) != (x, y):
            flags = (1 << 8) | (1 << 9) | (2 << 12)
            self.client_message(win, "_NET_MOVERESIZE_WINDOW", [flags, nx, ny, 0, 0])
            self.d.sync()

    def workarea(self):
        sw, sh = self.screen_size
        value = self._prop(self.root, "_NET_WORKAREA", Xatom.CARDINAL)
        if value is not None and len(value) >= 4 and value[2] > 0 and value[3] > 0:
            return int(value[0]), int(value[1]), min(int(value[2]), sw), min(int(value[3]), sh)
        return 0, 0, sw, sh

    def frame_extents(self, win):
        value = self._prop(win, "_NET_FRAME_EXTENTS", Xatom.CARDINAL)
        if value is not None and len(value) >= 4:
            return tuple(int(v) for v in value[:4])
        return 0, 0, 0, 0

    def unmaximize(self, win):
        state = self._prop(win, "_NET_WM_STATE", Xatom.ATOM)
        maximized = [self.atom("_NET_WM_STATE_MAXIMIZED_VERT"), self.atom("_NET_WM_STATE_MAXIMIZED_HORZ")]
        fullscreen = self.atom("_NET_WM_STATE_FULLSCREEN")
        if state is None:
            return
        if any(a in state for a in maximized):
            self.client_message(win, "_NET_WM_STATE", [0, maximized[0], maximized[1], 2, 0])
        if fullscreen in state:
            self.client_message(win, "_NET_WM_STATE", [0, fullscreen, 0, 2, 0])

    def resize(self, wid, w, h):
        win = self.window(wid)
        ax, ay, aw, ah = self.workarea()
        left, right, top, bottom = self.frame_extents(win)
        il, ir, it, ib = self.insets(win)
        w = max(1, min(int(w), aw - left - right))
        h = max(1, min(int(h), ah - top - bottom))
        self.unmaximize(win)
        flags = (1 << 10) | (1 << 11) | (2 << 12)
        data = [flags, 0, 0, w + il + ir, h + it + ib]
        geo = self.geometry(win)
        if geo:
            x, y = geo[0], geo[1]
            nx = min(max(x, ax + left), ax + aw - right - w)
            ny = min(max(y, ay + top), ay + ah - bottom - h)
            if (nx, ny) != (x, y):
                data = [flags | (1 << 8) | (1 << 9) | 10, nx - il, ny - it, w + il + ir, h + it + ib]
        self.client_message(win, "_NET_MOVERESIZE_WINDOW", data)
        self.d.sync()

    def close(self, wid):
        self.client_message(self.window(wid), "_NET_CLOSE_WINDOW", [X.CurrentTime, 2, 0, 0, 0])

    def to_root(self, wid, x, y):
        geo = self.geometry(self.window(wid))
        if not geo:
            return None
        return geo[0] + int(x), geo[1] + int(y)

    def motion(self, rx, ry):
        xtest.fake_input(self.d, X.MotionNotify, x=rx, y=ry)

    def button(self, number, pressed):
        xtest.fake_input(self.d, X.ButtonPress if pressed else X.ButtonRelease, number)

    def key(self, keycode, pressed):
        xtest.fake_input(self.d, X.KeyPress if pressed else X.KeyRelease, keycode)

    def flush(self):
        self.d.sync()


class Keyboard:

    POOL = 24
    REMAP_DELAY = 0.025
    REUSE_AFTER = 0.25

    def __init__(self, desktop):
        self.x = desktop
        d = desktop.d
        first, last = d.display.info.min_keycode, d.display.info.max_keycode
        mapping = d.get_keyboard_mapping(first, last - first + 1)
        def is_spare(syms):
            values = [s for s in syms if s]
            return not values or (len(set(values)) == 1 and values[0] >= 0x01000000)
        self.spare = [first + i for i, syms in enumerate(mapping) if is_spare(syms) and first + i > 8][-self.POOL:]
        self.assigned = {}
        self.shift = d.keysym_to_keycode(0xFFE1)

    @staticmethod
    def keysym(char):
        cp = ord(char)
        if char == "\n":
            return KEYSYM_RETURN
        if char == "\t":
            return KEYSYM_TAB
        if 0x20 <= cp <= 0x7E or 0xA0 <= cp <= 0xFF:
            return cp
        return 0x01000000 | cp

    def existing(self, sym):
        for code, index in self.x.d.keysym_to_keycodes(sym):
            if code in self.spare:
                continue
            if index in (0, 1):
                return code, index == 1
        return None

    def spare_code(self, sym):
        d = self.x.d
        now = time.monotonic()
        if sym in self.assigned:
            code, _ = self.assigned[sym]
            self.assigned[sym] = (code, now)
            return code
        used = {code for code, _ in self.assigned.values()}
        free = [c for c in self.spare if c not in used]
        if free:
            code = free[0]
        else:
            if not self.assigned:
                return None
            old_sym = min(self.assigned, key=lambda k: self.assigned[k][1])
            code, last_used = self.assigned.pop(old_sym)
            wait = self.REUSE_AFTER - (now - last_used)
            if wait > 0:
                time.sleep(wait)
        d.change_keyboard_mapping(code, [(sym, sym, sym, sym)])
        d.sync()
        time.sleep(self.REMAP_DELAY)
        self.assigned[sym] = (code, time.monotonic())
        return code

    def type(self, text):
        for char in text:
            sym = self.keysym(char)
            found = self.existing(sym)
            if found:
                code, needs_shift = found
            else:
                code, needs_shift = self.spare_code(sym), False
            if not code:
                continue
            if needs_shift and self.shift:
                self.x.key(self.shift, True)
            self.x.key(code, True)
            self.x.key(code, False)
            if needs_shift and self.shift:
                self.x.key(self.shift, False)
            self.x.flush()

    def restore(self):
        for code, _ in self.assigned.values():
            self.x.d.change_keyboard_mapping(code, [(0, 0, 0, 0)])
        self.assigned.clear()
        self.x.d.sync()



def drop_files(desktop, wid, root_x, root_y, uris):
    x = desktop
    d = x.d
    target = None
    win = x.window(wid)
    for _ in range(4):
        aware = x._prop(win, "XdndAware", Xatom.ATOM)
        if aware is not None:
            target, version = win, min(5, int(aware[0]) if len(aware) else 5)
            break
        try:
            parent = win.query_tree().parent
        except error.XError:
            break
        if not parent or parent.id == x.root.id:
            break
        win = parent
    if target is None:
        return False

    helper = x.helper.id
    uri_list = ("\r\n".join(uris) + "\r\n").encode()
    uri_atom = x.atom("text/uri-list")
    selection = x.atom("XdndSelection")
    x.helper.set_selection_owner(selection, X.CurrentTime)
    x.motion(root_x, root_y)
    d.sync()

    def send(name, data):
        x.client_message(target, name, [helper] + data, target=target)

    send("XdndEnter", [version << 24, uri_atom, 0, 0])
    send("XdndPosition", [0, (root_x << 16) | root_y, X.CurrentTime, x.atom("XdndActionCopy")])

    accepted, dropped, deadline = None, False, time.monotonic() + 3
    while time.monotonic() < deadline:
        while d.pending_events():
            ev = d.next_event()
            if ev.type == X.ClientMessage and ev.window.id == helper:
                name = d.get_atom_name(ev.client_type)
                if name == "XdndStatus" and accepted is None:
                    accepted = bool(ev.data[1][1] & 1)
                    if accepted:
                        send("XdndDrop", [0, X.CurrentTime, 0, 0])
                        dropped = True
                    else:
                        send("XdndLeave", [0, 0, 0, 0])
                        return False
                elif name == "XdndFinished":
                    return True
            elif ev.type == X.SelectionRequest and ev.owner.id == helper:
                prop = ev.property or ev.target
                ok = ev.target == uri_atom or d.get_atom_name(ev.target) in ("text/uri-list", "text/plain", "UTF8_STRING")
                if ok:
                    ev.requestor.change_property(prop, ev.target, 8, uri_list)
                notify = xevent.SelectionNotify(time=ev.time, requestor=ev.requestor, selection=ev.selection,
                                                target=ev.target, property=prop if ok else X.NONE)
                ev.requestor.send_event(notify)
                d.flush()
        time.sleep(0.01)
    if not dropped:
        send("XdndLeave", [0, 0, 0, 0])
    return dropped



CLIPBOARD_TARGETS = ["UTF8_STRING", "text/plain;charset=utf-8", "STRING", "TEXT", "text/plain"]
IMAGE_TARGET = "image/png"
CLIPBOARD_MAX = 32 << 20
INCR_CHUNK = 64 * 1024


class Clipboard:

    def __init__(self, desktop):
        self.x = desktop
        self.window = desktop.helper
        self.selection = desktop.atom("CLIPBOARD")
        self.prop = desktop.atom("LINMO_CLIPBOARD")
        self.incr_atom = desktop.atom("INCR")
        self.text = None
        self.png = None
        self.fetch = None
        self.outgoing = {}
        self.available = False
        d = desktop.d
        if xfixes is None or not d.has_extension("XFIXES"):
            log("XFIXES unavailable: no copy-paste")
            return
        try:
            d.xfixes_query_version()
            d.xfixes_select_selection_input(self.window, self.selection, xfixes.XFixesSetSelectionOwnerNotifyMask)
            d.sync()
            self.available = True
        except error.XError as exc:
            log("XFIXES selection input failed:", exc)

    def set_from_mac(self, text=None, png=None):
        if text is not None and len(text.encode("utf-8")) > CLIPBOARD_MAX:
            text = None
        if png is not None and len(png) > CLIPBOARD_MAX:
            png = None
        if text is None and png is None:
            return
        self.text, self.png = text, png
        self.fetch = None
        self.window.set_selection_owner(self.selection, X.CurrentTime)
        self.x.d.flush()


    def _request(self, target, time_):
        self.window.convert_selection(self.selection, self.x.atom(target), self.prop, time_)
        self.x.d.flush()

    def _next(self):
        fetch = self.fetch
        if fetch["queue"]:
            self._request(fetch["queue"][0], fetch["time"])
            return None
        self.fetch = None
        result = fetch["result"]
        message = {}
        for target in CLIPBOARD_TARGETS:
            if result.get(target):
                message["text"] = result[target].decode("latin-1" if target == "STRING" else "utf-8", "replace")
                break
        if result.get(IMAGE_TARGET):
            message["image"] = base64.b64encode(result[IMAGE_TARGET]).decode()
        return message or None

    def _received(self, target, data):
        fetch = self.fetch
        if fetch is None or not fetch["queue"] or fetch["queue"][0] != target:
            return None
        fetch["queue"].pop(0)
        if target == "TARGETS":
            names = set()
            for atom in data:
                try:
                    names.add(self.x.d.get_atom_name(atom))
                except error.XError:
                    pass
            text = next((t for t in CLIPBOARD_TARGETS if t in names), None)
            fetch["queue"] = ([text] if text else []) + ([IMAGE_TARGET] if IMAGE_TARGET in names else [])
        elif data:
            fetch["result"][target] = bytes(data)
            if target in CLIPBOARD_TARGETS:
                fetch["queue"] = [t for t in fetch["queue"] if t not in CLIPBOARD_TARGETS]
        return self._next()

    def handle_event(self, ev):
        if ev.type in (X.SelectionNotify, X.SelectionRequest, X.SelectionClear) and not hasattr(ev, "selection"):
            return None
        if ev.type == X.PropertyNotify and not hasattr(ev, "atom"):
            return None
        if type(ev).__name__ == "SetSelectionOwnerNotify":
            owner = getattr(ev.owner, "id", ev.owner)
            if ev.selection == self.selection and owner not in (0, self.window.id):
                self.text = self.png = None
                self.fetch = {"queue": ["TARGETS"], "result": {}, "time": ev.selection_timestamp, "incr": None}
                self._request("TARGETS", ev.selection_timestamp)
        elif ev.type == X.SelectionNotify and ev.selection == self.selection and ev.requestor.id == self.window.id:
            if self.fetch is None:
                return None
            target = self.x.d.get_atom_name(ev.target)
            if ev.property == X.NONE:
                if target == "TARGETS":
                    self.fetch["queue"] = ["UTF8_STRING", "STRING"]
                    return self._next()
                return self._received(target, b"")
            prop = self.window.get_full_property(self.prop, X.AnyPropertyType, sizehint=CLIPBOARD_MAX // 4)
            self.window.delete_property(self.prop)
            self.x.d.flush()
            if prop is None:
                return self._received(target, b"")
            if prop.property_type == self.incr_atom:
                self.fetch["incr"] = {"target": target, "data": bytearray()}
                return None
            value = prop.value
            if target == "TARGETS":
                return self._received(target, list(value) if prop.format == 32 else [])
            if prop.format != 8:
                return self._received(target, b"")
            return self._received(target, value if isinstance(value, bytes) else bytes(value))
        elif ev.type == X.PropertyNotify:
            return self._property_changed(ev)
        elif ev.type == X.SelectionRequest and ev.selection == self.selection:
            self._answer(ev)
        elif ev.type == X.SelectionClear and ev.selection == self.selection:
            self.text = self.png = None
        return None

    def _property_changed(self, ev):
        window_id = ev.window.id if hasattr(ev.window, "id") else ev.window
        incr = self.fetch and self.fetch.get("incr")
        if incr and window_id == self.window.id and ev.atom == self.prop and ev.state == X.PropertyNewValue:
            prop = self.window.get_full_property(self.prop, X.AnyPropertyType, sizehint=INCR_CHUNK)
            self.window.delete_property(self.prop)
            self.x.d.flush()
            chunk = b"" if prop is None else (prop.value if isinstance(prop.value, bytes) else bytes(prop.value))
            if chunk:
                incr["data"] += chunk
                if len(incr["data"]) > CLIPBOARD_MAX:
                    self.fetch = None
                return None
            self.fetch["incr"] = None
            return self._received(incr["target"], bytes(incr["data"]))
        key = (window_id, ev.atom)
        transfer = self.outgoing.get(key)
        if transfer and ev.state == X.PropertyDelete:
            chunk = transfer["data"][transfer["offset"]:transfer["offset"] + INCR_CHUNK]
            transfer["offset"] += len(chunk)
            try:
                transfer["window"].change_property(ev.atom, transfer["type"], 8, chunk)
            except (error.XError, struct.error):
                chunk = b""
            if not chunk:
                del self.outgoing[key]
            self.x.d.flush()
        return None


    def _targets(self):
        return (["TARGETS"] + (CLIPBOARD_TARGETS if self.text is not None else [])
                + ([IMAGE_TARGET] if self.png is not None else []))

    def _answer(self, ev):
        d = self.x.d
        prop = ev.property if ev.property != X.NONE else ev.target
        target = d.get_atom_name(ev.target)
        try:
            data, kind = None, None
            if target == "TARGETS" and (self.text is not None or self.png is not None):
                atoms = [self.x.atom(name) for name in self._targets()]
                ev.requestor.change_property(prop, Xatom.ATOM, 32, atoms)
            elif target in CLIPBOARD_TARGETS and self.text is not None:
                encoding = "latin-1" if target == "STRING" else "utf-8"
                kind = Xatom.STRING if target == "STRING" else self.x.atom("UTF8_STRING")
                data = self.text.encode(encoding, "replace")
            elif target == IMAGE_TARGET and self.png is not None:
                kind, data = self.x.atom(IMAGE_TARGET), self.png
            else:
                prop = X.NONE
            if data is not None:
                if len(data) > INCR_CHUNK:
                    ev.requestor.change_attributes(event_mask=X.PropertyChangeMask)
                    ev.requestor.change_property(prop, self.incr_atom, 32, [len(data)])
                    self.outgoing[(ev.requestor.id, prop)] = {"window": ev.requestor, "data": data,
                                                              "offset": 0, "type": kind}
                else:
                    ev.requestor.change_property(prop, kind, 8, data)
        except (error.XError, struct.error):
            prop = X.NONE
        reply = xevent.SelectionNotify(time=ev.time, requestor=ev.requestor, selection=ev.selection,
                                       target=ev.target, property=prop)
        ev.requestor.send_event(reply)
        d.flush()


def drag_out(desktop):
    x = desktop
    d = x.d
    catcher = x.catcher
    sw, sh = x.screen_size
    catcher.configure(x=sw - 24, y=sh - 24, stack_mode=X.Above)
    catcher.map()
    d.sync()
    uri_atom = x.atom("text/uri-list")
    result_prop = x.atom("LINMO_DRAG")
    copy = x.atom("XdndActionCopy")

    for step in range(3):
        x.motion(sw - 12 - step, sh - 12)
        d.sync()
        time.sleep(0.03)

    source, types, released, uris = None, [], False, None
    deadline = time.monotonic() + 1.5
    try:
        while time.monotonic() < deadline and uris is None:
            while d.pending_events():
                ev = d.next_event()
                if ev.type == X.ClientMessage and ev.window.id == catcher.id:
                    name = d.get_atom_name(ev.client_type)
                    data = ev.data[1]
                    if name == "XdndEnter":
                        source = data[0]
                        if data[1] & 1:
                            listed = x._prop(x.window(source), "XdndTypeList", Xatom.ATOM)
                            types = list(listed) if listed is not None else []
                        else:
                            types = [t for t in data[2:5] if t]
                        if uri_atom not in types:
                            return None
                        deadline = time.monotonic() + 3
                    elif name == "XdndPosition" and source:
                        x.client_message(x.window(source), "XdndStatus", [catcher.id, 1 | 2, 0, 0, copy],
                                         target=x.window(source))
                        if not released:
                            x.button(1, False)
                            d.sync()
                            released = True
                    elif name == "XdndDrop" and source:
                        catcher.convert_selection(x.atom("XdndSelection"), uri_atom, result_prop, data[2])
                        d.flush()
                    elif name == "XdndLeave":
                        return None
                elif ev.type == X.SelectionNotify and ev.requestor.id == catcher.id:
                    value = None
                    if ev.property != X.NONE:
                        prop = catcher.get_full_property(result_prop, X.AnyPropertyType)
                        value = prop.value if prop else None
                    raw = value.decode("utf-8", "replace") if isinstance(value, bytes) else (value or "")
                    uris = [u.strip() for u in raw.splitlines() if u.strip() and not u.startswith("#")]
                    if source:
                        x.client_message(x.window(source), "XdndFinished", [catcher.id, 1, copy, 0, 0],
                                         target=x.window(source))
            time.sleep(0.01)
    finally:
        catcher.unmap()
        d.sync()

    if not uris:
        return None
    from urllib.parse import unquote, urlparse
    paths = []
    for uri in uris:
        parsed = urlparse(uri)
        if parsed.scheme == "file":
            path = unquote(parsed.path)
            if os.path.isfile(path):
                paths.append(path)
    return paths or None


def pack_files(paths, limit=1 << 30):
    entries, blobs, total = [], [], 0
    for path in paths:
        size = os.path.getsize(path)
        if total + size > limit:
            break
        with open(path, "rb") as f:
            blobs.append(f.read())
        entries.append({"name": os.path.basename(path), "size": size})
        total += size
    meta = json.dumps({"files": entries}, ensure_ascii=False).encode()
    return struct.pack("<I", len(meta)) + meta + b"".join(blobs)


def receive_drop(payload):
    (json_len,) = struct.unpack_from("<I", payload)
    meta = json.loads(payload[4:4 + json_len])
    offset = 4 + json_len
    folder = os.path.join(os.path.expanduser("~/Downloads"), "LinMO")
    os.makedirs(folder, exist_ok=True)
    paths = []
    for item in meta.get("files", []):
        name = os.path.basename(item["name"]) or "file"
        size = int(item["size"])
        path = os.path.join(folder, name)
        stem, ext = os.path.splitext(name)
        n = 2
        while os.path.exists(path):
            path = os.path.join(folder, f"{stem} {n}{ext}")
            n += 1
        with open(path, "wb") as f:
            f.write(payload[offset:offset + size])
        offset += size
        paths.append(path)
    return meta, paths


def file_uri(path):
    from urllib.parse import quote
    return "file://" + quote(path)



def apply_scale(scale):
    desktop = (os.environ.get("XDG_CURRENT_DESKTOP") or "").upper()
    scale = 2 if scale >= 2 else 1
    os.environ["GDK_SCALE"] = str(scale)
    os.environ["QT_SCALE_FACTOR"] = str(scale)
    commands = []
    if "XFCE" in desktop and shutil.which("xfconf-query"):
        commands += [
            ["xfconf-query", "-c", "xsettings", "-p", "/Gdk/WindowScalingFactor", "-n", "-t", "int", "-s", str(scale)],
            ["xfconf-query", "-c", "xfwm4", "-p", "/general/theme", "-n", "-t", "string",
             "-s", "Default-xhdpi" if scale == 2 else "Default"],
        ]
    if "GNOME" in desktop and shutil.which("gsettings"):
        commands.append(["gsettings", "set", "org.gnome.desktop.interface", "scaling-factor", str(scale)])
    for command in commands:
        subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)



ICON_DIRS = ["/usr/share/icons", "/usr/local/share/icons", os.path.expanduser("~/.local/share/icons"),
             "/var/lib/flatpak/exports/share/icons"]
ICON_THEMES = ["hicolor", "Adwaita", "elementary-xfce", "elementary", "Papirus", "Yaru", "breeze", "gnome"]
ICON_SIZES = ["64x64", "48x48", "128x128", "96x96", "256x256", "scalable"]


def find_icon(name):
    if not name:
        return None
    if os.path.isabs(name):
        return name if os.path.isfile(name) else None
    for base in ICON_DIRS:
        for theme in ICON_THEMES:
            for size in ICON_SIZES:
                for ext in (".png", ".svg"):
                    path = os.path.join(base, theme, size, "apps", name + ext)
                    if os.path.isfile(path):
                        return path
    for ext in (".png", ".svg"):
        path = os.path.join("/usr/share/pixmaps", name + ext)
        if os.path.isfile(path):
            return path
    return None


_svg_cache = {}


def svg_to_png(path, size=128):
    try:
        key = (path, os.path.getmtime(path))
    except OSError:
        return None
    if key in _svg_cache:
        return _svg_cache[key]
    png = None
    if shutil.which("rsvg-convert"):
        try:
            out = subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), "-a", path],
                                 capture_output=True, timeout=5)
            if out.returncode == 0 and out.stdout.startswith(b"\x89PNG"):
                png = out.stdout
        except (OSError, subprocess.TimeoutExpired):
            pass
    if png is None:
        try:
            import gi
            gi.require_version("GdkPixbuf", "2.0")
            from gi.repository import GdkPixbuf
            pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_size(path, size, size)
            ok, data = pixbuf.save_to_bufferv("png", [], [])
            png = bytes(data) if ok else None
        except Exception:
            png = None
    _svg_cache[key] = png
    return png


def list_apps(with_icons=True):
    dirs = ["/usr/share/applications", "/usr/local/share/applications",
            "/var/lib/snapd/desktop/applications", "/var/lib/flatpak/exports/share/applications",
            os.path.expanduser("~/.local/share/applications")]
    lang = (os.environ.get("LANG") or "").split(".")[0]
    apps = {}
    for directory in dirs:
        for path in glob.glob(os.path.join(directory, "*.desktop")):
            parser = configparser.ConfigParser(interpolation=None, strict=False)
            parser.optionxform = str
            try:
                parser.read(path, encoding="utf-8")
                entry = parser["Desktop Entry"]
            except Exception:
                continue
            if entry.get("Type") != "Application" or entry.get("NoDisplay", "").lower() == "true" \
                    or entry.get("Hidden", "").lower() == "true" or not entry.get("Exec"):
                continue
            app_id = os.path.basename(path)[:-len(".desktop")]
            name = entry.get(f"Name[{lang}]") or entry.get(f"Name[{lang[:2]}]") or entry.get("Name") or app_id
            app = {
                "id": app_id,
                "name": name,
                "generic": entry.get("GenericName", ""),
                "categories": [c for c in entry.get("Categories", "").split(";") if c],
                "path": path,
            }
            if with_icons:
                icon_path = find_icon(entry.get("Icon", ""))
                if icon_path and os.path.getsize(icon_path) <= 256 * 1024:
                    png = svg_to_png(icon_path) if icon_path.endswith(".svg") else None
                    if png is not None:
                        app["icon"], app["iconFormat"] = base64.b64encode(png).decode(), "png"
                    else:
                        with open(icon_path, "rb") as f:
                            app["icon"] = base64.b64encode(f.read()).decode()
                        app["iconFormat"] = "svg" if icon_path.endswith(".svg") else "png"
            apps[app_id] = app
    return sorted(apps.values(), key=lambda a: a["name"].lower())


def launch(app_id):
    apps = {a["id"]: a for a in list_apps(with_icons=False)}
    app = apps.get(app_id)
    if not app:
        return
    env = dict(os.environ, GDK_BACKEND="x11", QT_QPA_PLATFORM="xcb", MOZ_ENABLE_WAYLAND="0",
               SDL_VIDEODRIVER="x11", ELECTRON_OZONE_PLATFORM_HINT="x11")
    env.pop("WAYLAND_DISPLAY", None)
    for command in (["gtk-launch", app_id], ["gio", "launch", app["path"]]):
        if shutil.which(command[0]):
            subprocess.Popen(command, start_new_session=True, env=env,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return
    log("no launcher (gtk-launch / gio) for", app_id)


def public_apps():
    return {"apps": [{k: v for k, v in a.items() if k != "path"} for a in list_apps()]}


IN_MODIFY = 0x00000002
IN_ATTRIB = 0x00000004
IN_CLOSE_WRITE = 0x00000008
IN_MOVED_FROM = 0x00000040
IN_MOVED_TO = 0x00000080
IN_CREATE = 0x00000100
IN_DELETE = 0x00000200
IN_IGNORED = 0x00008000
IN_NONBLOCK = 0o4000
IN_CLOEXEC = 0o2000000
LOCAL_MASK = IN_MODIFY | IN_ATTRIB | IN_CLOSE_WRITE | IN_MOVED_FROM | IN_MOVED_TO | IN_CREATE | IN_DELETE
INOTIFY_EVENT = struct.Struct("iIII")


class FolderSync:
    TAG = "linmo"
    PREFIX = ".linmo-refresh-"
    SETTLE = 0.8
    LOCAL_WINDOW = 3.0
    VIEW_INTERVAL = 3.0
    RESCAN_INTERVAL = 20.0
    MAX_CHILDREN = 512

    def __init__(self):
        self.root = None
        self.dev = None
        self.watches = {}
        self.watched = {}
        self.notifiers = []
        self.viewed = set()
        self.viewed_at = 0.0
        self.scanned_at = float("-inf")
        self.local = {}
        self.pending = {}
        self.known = {}
        self.counter = 0
        self.libc = None
        self.fd = -1
        try:
            self.libc = ctypes.CDLL(ctypes.util.find_library("c") or "libc.so.6", use_errno=True)
            self.fd = self.libc.inotify_init1(IN_NONBLOCK | IN_CLOEXEC)
        except (OSError, AttributeError):
            self.fd = -1
        self.locate()

    def fileno(self):
        return self.fd

    @staticmethod
    def unescape(field):
        for code, char in (("\\040", " "), ("\\011", "\t"), ("\\012", "\n"), ("\\134", "\\")):
            field = field.replace(code, char)
        return field

    def locate(self):
        if self.root and os.path.ismount(self.root):
            return self.root
        self.root = None
        try:
            with open("/proc/self/mountinfo", encoding="utf-8", errors="surrogateescape") as f:
                for line in f:
                    left, _, right = line.partition(" - ")
                    fields, extra = left.split(), right.split()
                    if len(fields) > 4 and len(extra) >= 2 and extra[0] == "virtiofs" and extra[1] == self.TAG:
                        self.root = self.unescape(fields[4])
                        break
            if self.root:
                self.dev = os.stat(self.root).st_dev
        except OSError:
            self.root = None
        return self.root

    def inode(self, path):
        try:
            st = os.stat(path)
        except OSError:
            return None
        return st.st_ino if st.st_dev == self.dev else None

    @staticmethod
    def signature(path):
        try:
            st = os.lstat(path)
        except OSError:
            return None
        return (st.st_ino, st.st_size, st.st_mtime_ns, st.st_mode)

    def find_notifiers(self):
        found = []
        me = str(os.getpid())
        for pid in os.listdir("/proc"):
            if not pid.isdigit() or pid == me:
                continue
            base = f"/proc/{pid}/fd"
            try:
                fds = os.listdir(base)
            except OSError:
                continue
            for fd in fds:
                try:
                    if os.readlink(f"{base}/{fd}") == "anon_inode:inotify":
                        found.append(f"/proc/{pid}/fdinfo/{fd}")
                except OSError:
                    continue
        return found

    def refresh(self, now, full=False):
        self.viewed_at = now
        if self.dev is None:
            return
        if full or now - self.scanned_at >= self.RESCAN_INTERVAL:
            self.scanned_at = now
            self.notifiers = self.find_notifiers()
        major, minor = os.major(self.dev), os.minor(self.dev)
        viewed, alive = set(), []
        for info in self.notifiers:
            try:
                with open(info) as f:
                    lines = f.readlines()
            except OSError:
                continue
            alive.append(info)
            for line in lines:
                if not line.startswith("inotify "):
                    continue
                fields = dict(part.split(":", 1) for part in line.split()[1:] if ":" in part)
                try:
                    sdev = int(fields.get("sdev", "0"), 16)
                    if (sdev >> 20, sdev & 0xFFFFF) == (major, minor):
                        viewed.add(int(fields.get("ino", "0"), 16))
                except ValueError:
                    continue
        self.notifiers = alive
        self.viewed = viewed
        self.sync_watches()

    def children(self, base):
        found = []
        try:
            with os.scandir(base) as entries:
                for entry in entries:
                    if len(found) >= self.MAX_CHILDREN:
                        break
                    try:
                        if entry.is_dir(follow_symlinks=False):
                            found.append(entry.path)
                    except OSError:
                        continue
        except OSError:
            pass
        return found

    def sync_watches(self):
        if self.fd < 0 or not self.root:
            return
        wanted = set()
        for base in {self.root, *self.watched}:
            for path in [base] + self.children(base):
                if self.inode(path) in self.viewed:
                    wanted.add(path)
        for path in list(self.watched):
            if path not in wanted and self.inode(path) not in self.viewed:
                self.unwatch(path)
        for path in wanted:
            self.watch(path)

    def watch(self, path):
        if self.fd < 0 or path in self.watched:
            return
        wd = self.libc.inotify_add_watch(self.fd, os.fsencode(path), LOCAL_MASK)
        if wd >= 0:
            old = self.watches.get(wd)
            if old is not None:
                self.watched.pop(old, None)
            self.watched[path] = wd
            self.watches[wd] = path

    def unwatch(self, path):
        wd = self.watched.pop(path, None)
        if wd is None:
            return
        self.watches.pop(wd, None)
        self.libc.inotify_rm_watch(self.fd, wd)

    def read_local(self):
        now = time.monotonic()
        while True:
            try:
                data = os.read(self.fd, 65536)
            except OSError:
                return
            if not data:
                return
            offset = 0
            while offset + INOTIFY_EVENT.size <= len(data):
                wd, mask, _, length = INOTIFY_EVENT.unpack_from(data, offset)
                name = data[offset + INOTIFY_EVENT.size:offset + INOTIFY_EVENT.size + length].rstrip(b"\0")
                offset += INOTIFY_EVENT.size + length
                base = self.watches.get(wd)
                if base is None:
                    continue
                if mask & IN_IGNORED:
                    self.watches.pop(wd, None)
                    if self.watched.get(base) == wd:
                        self.watched.pop(base, None)
                    continue
                if name:
                    self.local[os.path.join(base, os.fsdecode(name))] = now

    def changed(self, paths):
        if not isinstance(paths, list) or not self.locate():
            return
        now = time.monotonic()
        self.refresh(now, full=now - self.scanned_at >= self.VIEW_INTERVAL)
        for rel in paths:
            if not isinstance(rel, str):
                continue
            parts = [p for p in rel.split("/") if p not in ("", ".", "..")]
            if not parts or any(part.startswith(self.PREFIX) for part in parts):
                continue
            path = os.path.join(self.root, *parts)
            self.pending[path] = [now + self.SETTLE, self.signature(path), now]
            for depth in range(1, len(parts)):
                entry = self.pending.get(os.path.join(self.root, *parts[:depth]))
                if entry is not None:
                    entry[0] = now + self.SETTLE

    def deadline(self):
        due = min((entry[0] for entry in self.pending.values()), default=float("inf"))
        if self.root:
            due = min(due, self.viewed_at + self.VIEW_INTERVAL)
        return due

    def tick(self, now):
        if now - self.viewed_at >= self.VIEW_INTERVAL:
            if self.locate():
                self.refresh(now)
            else:
                self.viewed_at = now
            self.local = {p: t for p, t in self.local.items() if now - t < self.LOCAL_WINDOW * 2}
        ready = sorted(path for path, entry in self.pending.items() if entry[0] <= now)
        poked = []
        for path in ready:
            _, sig, arrived = self.pending.pop(path)
            current = self.signature(path)
            if current != sig:
                self.pending[path] = [now + self.SETTLE, current, arrived]
                continue
            if any(path.startswith(done + "/") for done in poked):
                self.remember(path, current)
                continue
            if self.local.get(path, float("-inf")) >= arrived - self.LOCAL_WINDOW:
                self.remember(path, current)
                continue
            parent = os.path.dirname(path)
            if self.inode(parent) not in self.viewed:
                self.remember(path, current)
                continue
            self.watch(parent)
            if self.poke(path, current):
                poked.append(path)

    def remember(self, path, sig):
        if len(self.known) > 50000:
            self.known.clear()
        if sig is None:
            self.known.pop(path, None)
        else:
            self.known[path] = sig[0]

    def poke(self, path, sig):
        try:
            if sig is None:
                try:
                    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                except FileExistsError:
                    self.move_through(path)
                else:
                    os.close(fd)
                    os.unlink(path)
            elif self.known.get(path) == sig[0] and not os.path.islink(path):
                os.chmod(path, sig[3] & 0o7777)
            else:
                self.move_through(path)
        except OSError as exc:
            log("folder refresh failed:", path, exc)
            return False
        self.local[path] = time.monotonic()
        self.remember(path, self.signature(path))
        return True

    def move_through(self, path):
        self.counter += 1
        temp = os.path.join(os.path.dirname(path), f"{self.PREFIX}{os.getpid()}-{self.counter}")
        inside = os.path.join(temp, "item")
        os.mkdir(temp, 0o700)
        try:
            os.rename(path, inside)
            for attempt in range(5):
                try:
                    os.rename(inside, path)
                    break
                except OSError as exc:
                    if attempt == 4:
                        log("folder refresh could not restore", path, "from", inside, exc)
                        raise
                    time.sleep(0.05)
        finally:
            try:
                os.rmdir(temp)
            except OSError:
                pass


class Tracked:

    def __init__(self, info):
        self.info = info
        self.damage = None
        self.dirty = None
        self.needs_full = True
        self.crc = None
        self.icon_sent = False
        self.offset = (0, 0)


class Agent:
    def __init__(self, desktop, channel, folders):
        self.x = desktop
        self.ch = channel
        self.folders = folders
        self.windows = {}
        self.streaming = False
        self.last_scan = 0.0
        self.last_frame = 0.0
        self.last_active = 0
        self.activated = 0

    def start(self):
        _, _, w, h = self.x.workarea()
        features = FEATURES + (["clipboard", "clipboard-image"] if self.x.clipboard.available else [])
        self.ch.send(MSG_HELLO, {"version": VERSION, "features": features, "screen": [w, h],
                                 "session": os.environ.get("XDG_SESSION_TYPE", "x11")})
        self.ch.send(MSG_APPS, public_apps())
        self.scan()


    def scan(self):
        found = {}
        for wid in self.x.client_list():
            win = self.x.window(wid)
            if not self.x.is_regular(win):
                continue
            geo = self.x.geometry(win)
            if not geo or geo[2] <= 1 or geo[3] <= 1:
                continue
            min_w, min_h = self.x.min_size(win)
            found[wid] = {
                "id": wid, "kind": "normal", "title": self.x.title(win), "app": self.x.app_id(win),
                "x": geo[0], "y": geo[1], "w": geo[2], "h": geo[3], "parent": self.x.transient_for(win),
                "minW": min_w, "minH": min_h,
            }
        for win, geo in self.x.popups():
            found[win.id] = {
                "id": win.id, "kind": "popup", "title": "", "app": self.x.app_id(win),
                "x": geo[0], "y": geo[1], "w": geo[2], "h": geo[3], "parent": self.last_active,
            }

        for wid in list(self.windows):
            if wid not in found:
                self.forget(wid)
                self.ch.send(MSG_WINDOW_CLOSED, {"id": wid})
        for wid, info in found.items():
            tracked = self.windows.get(wid)
            if tracked is None:
                tracked = self.windows[wid] = Tracked(info)
                self.watch(wid, tracked)
                self.ch.send(MSG_WINDOW, info)
            left, _, top, _ = self.x.insets(self.x.window(wid))
            if tracked.offset != (left, top):
                tracked.offset = (left, top)
                tracked.needs_full = True
            if tracked.info != info:
                if (tracked.info["w"], tracked.info["h"]) != (info["w"], info["h"]):
                    tracked.needs_full = True
                tracked.info = info
                self.ch.send(MSG_WINDOW, info)
            if self.streaming and not tracked.icon_sent and info["kind"] == "normal":
                self.send_icon(wid, tracked)

        active = self.x.active_window()
        if active != self.last_active and active in self.windows:
            self.last_active = active
            self.ch.send(MSG_FOCUSED, {"id": active})

    def watch(self, wid, tracked):
        if self.x.damage_event is None:
            return
        try:
            tracked.damage = self.x.window(wid).damage_create(xdamage.DamageReportBoundingBox)
        except Exception:
            tracked.damage = None

    def forget(self, wid):
        tracked = self.windows.pop(wid, None)
        if tracked and tracked.damage:
            try:
                self.x.d.damage_destroy(tracked.damage)
            except Exception:
                pass

    def drain_x_events(self):
        d = self.x.d
        while d.pending_events():
            ev = d.next_event()
            copied = self.x.clipboard.handle_event(ev)
            if copied:
                self.ch.send(MSG_CLIPBOARD, copied)
            if self.x.damage_event is not None and ev.type == self.x.damage_event:
                tracked = self.windows.get(ev.drawable.id if hasattr(ev.drawable, "id") else ev.drawable)
                if tracked is None:
                    continue
                a = ev.area
                left, top = tracked.offset
                rect = (a.x - left, a.y - top, a.x - left + a.width, a.y - top + a.height)
                if tracked.dirty is None:
                    tracked.dirty = rect
                else:
                    o = tracked.dirty
                    tracked.dirty = (min(o[0], rect[0]), min(o[1], rect[1]), max(o[2], rect[2]), max(o[3], rect[3]))

    def send_icon(self, wid, tracked):
        tracked.icon_sent = True
        icon = self.x.icon(self.x.window(wid))
        if icon:
            w, h, pixels = icon
            self.ch.send(MSG_ICON, struct.pack("<III", wid, w, h) + pixels)

    def send_frames(self):
        for wid, tracked in list(self.windows.items()):
            if self.ch.backlogged:
                return
            info = tracked.info
            w, h = info["w"], info["h"]
            ox, oy = tracked.offset

            if tracked.damage is not None and not tracked.needs_full:
                if tracked.dirty is None:
                    continue
                x0, y0, x1, y1 = tracked.dirty
                tracked.dirty = None
                self.x.d.damage_subtract(tracked.damage)
                x0, y0 = max(0, x0), max(0, y0)
                x1, y1 = min(w, x1), min(h, y1)
                if x1 <= x0 or y1 <= y0:
                    continue
                if (x1 - x0) * (y1 - y0) < FULL_FRAME_RATIO * w * h:
                    pixels = self.x.capture(self.x.window(wid), x0 + ox, y0 + oy, x1 - x0, y1 - y0)
                    if pixels is not None:
                        header = struct.pack("<IIIIIIII", wid, w, h, x0, y0, x1 - x0, y1 - y0, (x1 - x0) * 4)
                        self.ch.send(MSG_FRAME_RECT, header + pixels)
                    continue

            if tracked.damage is not None:
                tracked.dirty = None
                self.x.d.damage_subtract(tracked.damage)
            pixels = self.x.capture(self.x.window(wid), ox, oy, w, h)
            if pixels is None:
                continue
            if tracked.damage is None:
                crc = zlib.crc32(pixels)
                if crc == tracked.crc and not tracked.needs_full:
                    continue
                tracked.crc = crc
            tracked.needs_full = False
            self.ch.send(MSG_FRAME, struct.pack("<IIII", wid, w, h, w * 4) + pixels)


    def focus(self, wid):
        tracked = self.windows.get(wid)
        if tracked and tracked.info["kind"] == "normal" and self.activated != wid:
            self.x.activate(wid)
            self.x.ensure_on_screen(wid)
            self.activated = wid
            self.last_active = wid

    def handle(self, kind, msg):
        if kind == MSG_DROP:
            meta, paths = receive_drop(msg)
            wid = int(meta.get("id", 0))
            self.focus(wid)
            pos = self.x.to_root(wid, meta.get("x", 0), meta.get("y", 0))
            if pos and paths:
                ok = drop_files(self.x, wid, pos[0], pos[1], [file_uri(p) for p in paths])
                log("drop", "accepted" if ok else "not accepted — files saved to ~/Downloads/LinMO")
            return

        wid = int(msg.get("id", 0))
        if kind in (MSG_POINTER, MSG_BUTTON, MSG_SCROLL):
            if kind == MSG_BUTTON and msg.get("pressed"):
                self.focus(wid)
            pos = self.x.to_root(wid, msg.get("x", 0), msg.get("y", 0))
            if pos is None:
                return
            self.x.motion(*pos)
            if kind == MSG_BUTTON:
                self.x.button(int(msg.get("button", 1)), bool(msg.get("pressed")))
            elif kind == MSG_SCROLL:
                for number, steps in ((4, -int(msg.get("dy", 0))), (5, int(msg.get("dy", 0))),
                                      (6, -int(msg.get("dx", 0))), (7, int(msg.get("dx", 0)))):
                    for _ in range(max(0, min(steps, 20))):
                        self.x.button(number, True)
                        self.x.button(number, False)
            self.x.flush()
        elif kind == MSG_KEY:
            self.x.key(int(msg["keycode"]), bool(msg.get("pressed")))
            self.x.flush()
        elif kind == MSG_TEXT:
            self.x.keyboard.type(str(msg.get("text", "")))
        elif kind == MSG_FOCUS:
            self.focus(wid)
        elif kind == MSG_RESIZE:
            self.x.resize(wid, msg.get("w", 1), msg.get("h", 1))
        elif kind == MSG_CLOSE:
            self.x.close(wid)
        elif kind == MSG_LAUNCH:
            launch(str(msg.get("app", "")))
        elif kind == MSG_DRAG_OUT:
            paths = drag_out(self.x)
            if paths:
                self.ch.send(MSG_DRAG_DATA, pack_files(paths))
            else:
                self.ch.send(MSG_DRAG_NONE, {})
        elif kind == MSG_SET_CLIPBOARD:
            text = msg.get("text")
            image = msg.get("image")
            png = None
            if isinstance(image, str):
                try:
                    png = base64.b64decode(image)
                except ValueError:
                    pass
            self.x.clipboard.set_from_mac(text if isinstance(text, str) and text else None, png)
        elif kind == MSG_FOLDER_CHANGED:
            self.folders.changed(msg.get("paths"))
        elif kind == MSG_CONFIG:
            if "scale" in msg:
                apply_scale(float(msg["scale"]))
        elif kind == MSG_STREAM:
            self.streaming = bool(msg.get("enabled"))
            for tracked in self.windows.values():
                tracked.needs_full = True
                tracked.dirty = None
                tracked.crc = None
                tracked.icon_sent = False
            if self.streaming:
                for tracked in self.windows.values():
                    self.ch.send(MSG_WINDOW, tracked.info)
                self.ch.send(MSG_APPS, public_apps())

    def run(self):
        self.start()
        x_fd = self.x.d.fileno()
        while True:
            now = time.monotonic()
            deadline = min(self.last_scan + SCAN_INTERVAL,
                           self.last_frame + FRAME_INTERVAL if self.streaming else float("inf"),
                           self.folders.deadline())
            wait_w = [self.ch] if self.ch.outbox else []
            wait_r = [self.ch, x_fd] + ([self.folders] if self.folders.fd >= 0 else [])
            readable, writable, _ = select.select(wait_r, wait_w, [], max(0.0, deadline - now))
            if writable:
                self.ch.flush()
            if self.folders in readable:
                self.folders.read_local()
            if self.ch in readable:
                for kind, msg in self.ch.receive():
                    try:
                        self.handle(kind, msg)
                    except (error.XError, KeyError, ValueError, TypeError, OSError, struct.error) as exc:
                        log("command failed:", exc)
            self.drain_x_events()
            now = time.monotonic()
            try:
                self.folders.tick(now)
            except OSError as exc:
                log("folder refresh failed:", exc)
            if now - self.last_scan >= SCAN_INTERVAL:
                self.last_scan = now
                self.scan()
                self.drain_x_events()
            if self.streaming and now - self.last_frame >= FRAME_INTERVAL:
                self.last_frame = now
                self.send_frames()

    def stop(self):
        for wid in list(self.windows):
            self.forget(wid)
        try:
            self.x.keyboard.restore()
        except error.XError:
            pass


def main():
    try:
        desktop = Desktop()
    except Exception as exc:
        log("cannot open X display:", exc)
        return 1
    log("started on", os.environ.get("DISPLAY"), "screen", desktop.screen_size,
        "damage" if desktop.damage_event else "no-damage")
    folders = FolderSync()
    while True:
        channel = connect()
        if channel is None:
            time.sleep(2)
            continue
        log("connected to LinMO")
        agent = Agent(desktop, channel, folders)
        try:
            agent.run()
        except (EOFError, OSError) as exc:
            log("disconnected:", exc)
        finally:
            agent.stop()
            channel.close()
        time.sleep(1)


if __name__ == "__main__":
    sys.exit(main())
