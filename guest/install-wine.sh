#!/bin/sh
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then
    echo "กรุณารันด้วย sudo: sudo sh $0" >&2
    exit 1
fi

if ! command -v apt-get >/dev/null 2>&1 || ! command -v dpkg >/dev/null 2>&1; then
    echo "ตัวติดตั้ง Wine รองรับเฉพาะ Debian และ Ubuntu" >&2
    exit 1
fi

. /etc/os-release
BASE=""
CODENAME=""
case " $ID ${ID_LIKE:-} " in
    *" ubuntu "*)
        BASE=ubuntu
        CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
        ;;
    *" debian "*)
        BASE=debian
        CODENAME="${DEBIAN_CODENAME:-$VERSION_CODENAME}"
        ;;
esac
if [ -z "$BASE" ] || [ -z "$CODENAME" ]; then
    echo "ตัวติดตั้ง Wine รองรับเฉพาะ Debian และ Ubuntu (เครื่องนี้คือ ${PRETTY_NAME:-$ID})" >&2
    exit 1
fi

echo "▶ ตรวจ Rosetta…"
if [ ! -x /usr/local/sbin/linmo-rosetta ] && [ -f "$DIR/install.sh" ]; then
    sh "$DIR/install.sh"
fi
[ -x /usr/local/sbin/linmo-rosetta ] && /usr/local/sbin/linmo-rosetta || true
if [ ! -e /proc/sys/fs/binfmt_misc/rosetta ]; then
    echo "❌ ยังไม่พบ Rosetta — บน Mac ให้ปิดเครื่อง เปิด \"รันโปรแกรม x86_64 ผ่าน Rosetta\" ในการตั้งค่าเครื่อง แล้วเปิดเครื่องและรันคำสั่งนี้อีกครั้ง" >&2
    exit 1
fi
echo "  Rosetta พร้อมใช้"

export DEBIAN_FRONTEND=noninteractive

echo "▶ ล้างแพ็กเกจ i386 ที่ใช้ไม่ได้…"
dpkg --configure -a >/dev/null 2>&1 || true
I386="$(dpkg-query -W -f='${binary:Package}\n' 2>/dev/null | grep ':i386$' || true)"
if [ -n "$I386" ]; then
    apt-get purge -y -qq $I386 || dpkg --purge --force-all $I386 || true
fi
if dpkg --print-foreign-architectures | grep -qx i386; then
    dpkg --remove-architecture i386 || true
fi

echo "▶ เพิ่มสถาปัตยกรรม amd64…"
python3 - "$BASE" "$CODENAME" <<'PY'
import glob
import os
import re
import sys

base, codename = sys.argv[1], sys.argv[2]
native = os.popen("dpkg --print-architecture").read().strip() or "arm64"

def is_ports(text):
    return "ports.ubuntu.com" in text or "ubuntu-ports" in text

for path in glob.glob("/etc/apt/sources.list.d/*.sources"):
    if os.path.basename(path).startswith(("linmo-", "winehq")):
        continue
    with open(path) as f:
        stanzas = re.split(r"\n\s*\n", f.read().strip("\n"))
    changed = False
    out = []
    for stanza in stanzas:
        lines = stanza.split("\n")
        has_arch = any(l.lower().startswith("architectures:") for l in lines)
        if not has_arch and is_ports(stanza):
            idx = next((i for i, l in enumerate(lines) if l.lower().startswith("uris:")), len(lines) - 1)
            lines.insert(idx + 1, f"Architectures: {native}")
            changed = True
        out.append("\n".join(lines))
    if changed:
        with open(path, "w") as f:
            f.write("\n\n".join(out) + "\n")

for path in ["/etc/apt/sources.list"] + glob.glob("/etc/apt/sources.list.d/*.list"):
    if not os.path.exists(path):
        continue
    with open(path) as f:
        lines = f.read().split("\n")
    changed = False
    for i, line in enumerate(lines):
        s = line.strip()
        if not re.match(r"deb(-src)?\s", s) or not is_ports(s):
            continue
        m = re.match(r"(deb(?:-src)?)\s+\[([^\]]*)\]\s+(.*)", s)
        if m:
            if "arch=" in m.group(2):
                continue
            lines[i] = f"{m.group(1)} [{m.group(2).strip()} arch={native}] {m.group(3)}"
        else:
            kind, rest = s.split(None, 1)
            lines[i] = f"{kind} [arch={native}] {rest}"
        changed = True
    if changed:
        with open(path, "w") as f:
            f.write("\n".join(lines))

target = "/etc/apt/sources.list.d/linmo-amd64.sources"
if base == "ubuntu":
    keyring = "/usr/share/keyrings/ubuntu-archive-keyring.gpg"
    signed = f"Signed-By: {keyring}\n" if os.path.exists(keyring) else ""
    with open(target, "w") as f:
        f.write(
            "Types: deb\n"
            "URIs: http://archive.ubuntu.com/ubuntu\n"
            f"Suites: {codename} {codename}-updates {codename}-backports\n"
            "Components: main restricted universe multiverse\n"
            "Architectures: amd64\n"
            f"{signed}"
            "\n"
            "Types: deb\n"
            "URIs: http://security.ubuntu.com/ubuntu\n"
            f"Suites: {codename}-security\n"
            "Components: main restricted universe multiverse\n"
            "Architectures: amd64\n"
            f"{signed}"
        )
elif os.path.exists(target):
    os.remove(target)
PY
dpkg --add-architecture amd64

echo "▶ เพิ่มคลัง WineHQ ($BASE $CODENAME)…"
apt-get update -qq || true
apt-get install -y -qq ca-certificates wget >/dev/null
if ! wget -q --spider "https://dl.winehq.org/wine-builds/$BASE/dists/$CODENAME/Release"; then
    echo "❌ WineHQ ยังไม่มีแพ็กเกจสำหรับ $BASE $CODENAME" >&2
    exit 1
fi
install -d -m 0755 /etc/apt/keyrings
wget -q -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key
rm -f /etc/apt/sources.list.d/winehq*.sources /etc/apt/sources.list.d/winehq*.list
cat > "/etc/apt/sources.list.d/winehq-$CODENAME.sources" <<EOF
Types: deb
URIs: https://dl.winehq.org/wine-builds/$BASE
Suites: $CODENAME
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/winehq-archive.key
EOF

echo "▶ ติดตั้ง WineHQ (amd64 ผ่าน Rosetta)…"
[ -L "/usr/local/bin/*" ] && rm -f "/usr/local/bin/*"
apt-get update -qq
WINE_VERSION="$(apt-cache policy wine-stable:amd64 | awk '/Candidate:/ {print $2}')"
if [ -z "$WINE_VERSION" ] || [ "$WINE_VERSION" = "(none)" ]; then
    echo "❌ ไม่พบแพ็กเกจ wine-stable ในคลัง WineHQ" >&2
    exit 1
fi
if [ "$(dpkg-query -W -f='${Version} ${Architecture}' wine-stable-i386 2>/dev/null || true)" != "$WINE_VERSION amd64" ]; then
    WORK="$(mktemp -d)"
    chmod 0755 "$WORK"
    dpkg --add-architecture i386
    apt-get update -qq || true
    (cd "$WORK" && apt-get download -qq "wine-stable-i386:i386=$WINE_VERSION") || true
    dpkg --remove-architecture i386
    apt-get update -qq || true
    mkdir -p "$WORK/pkg/DEBIAN"
    DEB="$(ls "$WORK"/wine-stable-i386_*.deb 2>/dev/null | head -n 1)"
    if [ -n "$DEB" ]; then
        dpkg-deb -x "$DEB" "$WORK/full"
        if [ -d "$WORK/full/opt/wine-stable/lib/wine/i386-windows" ]; then
            mkdir -p "$WORK/pkg/opt/wine-stable/lib/wine"
            cp -a "$WORK/full/opt/wine-stable/lib/wine/i386-windows" "$WORK/pkg/opt/wine-stable/lib/wine/"
        fi
    fi
    cat > "$WORK/pkg/DEBIAN/control" <<CONTROL
Package: wine-stable-i386
Version: $WINE_VERSION
Architecture: amd64
Maintainer: LinMO <linmo@localhost>
Description: LinMO stand-in for wine-stable-i386 under Rosetta
CONTROL
    dpkg-deb --build --root-owner-group "$WORK/pkg" "$WORK/shim.deb" >/dev/null
    dpkg -i "$WORK/shim.deb"
    rm -rf "$WORK"
fi
apt-get install -y --install-recommends winehq-stable:amd64
WINE="$(command -v wine || true)"
if [ -z "$WINE" ]; then
    echo "❌ ติดตั้ง Wine แล้วแต่ไม่พบคำสั่ง wine" >&2
    exit 1
fi

echo "▶ ตั้งให้ดับเบิลคลิกไฟล์ .exe แล้วเปิดด้วย Wine…"
install -d /usr/share/applications
cat > /usr/share/applications/linmo-wine.desktop <<DESKTOP
[Desktop Entry]
Type=Application
Name=Wine
Comment=Run Windows programs
Exec=$WINE start /unix %f
Icon=wine
Terminal=false
NoDisplay=true
MimeType=application/x-ms-dos-executable;application/x-msdownload;application/x-msi;application/x-ms-shortcut;application/vnd.microsoft.portable-executable;
DESKTOP
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications || true
USER_HOME=""
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
    USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
fi
python3 - "$USER_HOME" "${SUDO_USER:-}" <<'PY'
import os
import pwd
import sys

home, user = sys.argv[1], sys.argv[2]
types = [
    "application/x-ms-dos-executable",
    "application/x-msdownload",
    "application/vnd.microsoft.portable-executable",
    "application/x-msi",
    "application/x-ms-shortcut",
]

def set_defaults(path):
    lines = open(path).read().split("\n") if os.path.exists(path) else []
    lines = [l for l in lines if l.split("=", 1)[0].strip() not in types]
    section = next((i for i, l in enumerate(lines) if l.strip() == "[Default Applications]"), None)
    entries = [f"{t}=linmo-wine.desktop" for t in types]
    if section is None:
        if lines and lines[-1].strip():
            lines.append("")
        lines += ["[Default Applications]"] + entries
    else:
        lines[section + 1:section + 1] = entries
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write("\n".join(lines).rstrip("\n") + "\n")

set_defaults("/etc/xdg/mimeapps.list")
set_defaults("/usr/share/applications/mimeapps.list")
if home and user:
    path = os.path.join(home, ".config", "mimeapps.list")
    existed = os.path.isdir(os.path.dirname(path))
    set_defaults(path)
    pw = pwd.getpwnam(user)
    os.chown(path, pw.pw_uid, pw.pw_gid)
    if not existed:
        os.chown(os.path.dirname(path), pw.pw_uid, pw.pw_gid)
PY

echo "▶ ทดสอบ Wine…"
if VERSION="$(wine --version 2>/dev/null)"; then
    echo "✅ ติดตั้ง $VERSION เสร็จแล้ว — เปิดโปรแกรม Windows ได้ด้วยคำสั่ง wine ชื่อไฟล์.exe หรือดับเบิลคลิกไฟล์ .exe"
else
    echo "⚠️  ติดตั้งแล้วแต่รัน wine ไม่ได้ — ลองรีสตาร์ทเครื่อง Linux แล้วพิมพ์ wine --version" >&2
fi
