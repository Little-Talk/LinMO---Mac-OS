#!/bin/sh
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then
    echo "กรุณารันด้วย sudo: sudo sh $0" >&2
    exit 1
fi

echo "▶ ติดตั้งแพ็กเกจที่ต้องใช้…"
if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq || true
    apt-get install -y -qq python3-xlib libgtk-3-bin librsvg2-bin || apt-get install -y -qq python3-xlib
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y -q python3-xlib gtk3 librsvg2-tools || dnf install -y -q python3-xlib
elif command -v zypper >/dev/null 2>&1; then
    zypper --non-interactive install python3-python-xlib || true
elif command -v pacman >/dev/null 2>&1; then
    pacman -S --noconfirm --needed python-xlib gtk3 librsvg || true
else
    echo "ไม่รู้จักตัวจัดการแพ็กเกจ — กรุณาติดตั้ง python3-xlib เอง" >&2
fi

echo "▶ คัดลอก agent…"
install -d /usr/local/lib/linmo
install -m 0755 "$DIR/linmo-agent.py" /usr/local/lib/linmo/linmo-agent.py

echo "▶ ตั้งให้เริ่มทำงานเมื่อเข้าสู่ระบบ…"
install -d /etc/xdg/autostart
cat > /etc/xdg/autostart/linmo-agent.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=LinMO Agent
Comment=Show Linux apps as separate windows on your Mac
Exec=python3 /usr/local/lib/linmo/linmo-agent.py
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

ARCH="$(uname -m)"
echo "▶ ติดตั้ง linmo-wayland ($ARCH)…"
if command -v apt-get >/dev/null 2>&1; then
    apt-get install -y -qq libxkbcommon0 libpixman-1-0 foot xwayland libegl1 >/dev/null 2>&1 || true
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y -q libxkbcommon pixman foot xorg-x11-server-Xwayland mesa-libEGL >/dev/null 2>&1 || true
elif command -v pacman >/dev/null 2>&1; then
    pacman -S --noconfirm --needed libxkbcommon pixman foot xorg-xwayland >/dev/null 2>&1 || true
fi

WAYLAND_OK=0
if [ -f "$DIR/linmo-wayland-$ARCH" ]; then
    install -m 0755 "$DIR/linmo-wayland-$ARCH" /usr/local/bin/linmo-wayland
    WAYLAND_OK=1
elif [ -d "$DIR/linmo-wayland-src" ] && command -v cargo >/dev/null 2>&1; then
    echo "  ไม่มีไฟล์สำเร็จรูปสำหรับ $ARCH — กำลังสร้างจากซอร์สโค้ด (อาจใช้เวลาหลายนาที)…"
    if command -v apt-get >/dev/null 2>&1; then
        apt-get install -y -qq libxkbcommon-dev libpixman-1-dev pkg-config >/dev/null 2>&1 || true
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y -q libxkbcommon-devel pixman-devel pkgconf-pkg-config >/dev/null 2>&1 || true
    fi
    BUILD="$(mktemp -d)"
    cp -r "$DIR/linmo-wayland-src/." "$BUILD/"
    if (cd "$BUILD" && cargo build --release --locked -q); then
        install -m 0755 "$BUILD/target/release/linmo-wayland" /usr/local/bin/linmo-wayland
        WAYLAND_OK=1
    else
        echo "  สร้าง linmo-wayland ไม่สำเร็จ (ต้องใช้ Rust 1.80 ขึ้นไป) — โหมด X11 ยังใช้ได้ตามปกติ" >&2
    fi
    rm -rf "$BUILD"
else
    echo "  ข้าม linmo-wayland: ยังไม่มีไฟล์สำหรับ $ARCH — โหมด X11 ยังใช้ได้ตามปกติ"
fi

if [ "$WAYLAND_OK" = 1 ]; then
    cat > /etc/xdg/autostart/linmo-wayland.desktop <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=LinMO Wayland
Comment=Run Wayland apps as separate windows on your Mac
Exec=/usr/local/bin/linmo-wayland
NoDisplay=true
X-GNOME-Autostart-enabled=true
DESKTOP
fi

echo "▶ ตั้งค่า Rosetta สำหรับโปรแกรม x86_64…"
install -d /usr/local/sbin
cat > /usr/local/sbin/linmo-rosetta <<'ROSETTA'
#!/bin/sh
mkdir -p /media/rosetta
if ! mountpoint -q /media/rosetta; then
    mount -t virtiofs -o ro rosetta /media/rosetta 2>/dev/null || exit 0
fi
[ -x /media/rosetta/rosetta ] || exit 0
if ! mountpoint -q /proc/sys/fs/binfmt_misc; then
    mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null || true
fi
[ -e /proc/sys/fs/binfmt_misc/rosetta ] && exit 0
printf '%s\n' ':rosetta:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00:\xff\xff\xff\xff\xff\xfe\xfe\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/media/rosetta/rosetta:CF' > /proc/sys/fs/binfmt_misc/register
ROSETTA
chmod 0755 /usr/local/sbin/linmo-rosetta
if command -v systemctl >/dev/null 2>&1; then
    cat > /etc/systemd/system/linmo-rosetta.service <<'UNIT'
[Unit]
Description=LinMO: register Rosetta for x86_64 programs
After=local-fs.target proc-sys-fs-binfmt_misc.mount systemd-binfmt.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/linmo-rosetta
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload || true
    systemctl enable linmo-rosetta.service >/dev/null 2>&1 || true
fi
/usr/local/sbin/linmo-rosetta || true
if [ -e /proc/sys/fs/binfmt_misc/rosetta ]; then
    echo "  เปิดใช้ Rosetta แล้ว"
else
    echo "  ยังไม่พบ Rosetta — เปิด Rosetta ในการตั้งค่าเครื่องบน Mac แล้วรีสตาร์ทเครื่อง จากนั้นรันคำสั่งติดตั้งนี้อีกครั้ง"
fi

echo "✅ ติดตั้งเสร็จแล้ว — ออกจากระบบแล้วเข้าใหม่ (หรือรีสตาร์ทเครื่อง) เพื่อเริ่มใช้งาน"
if [ "${XDG_SESSION_TYPE:-}" = "wayland" ] && [ "$WAYLAND_OK" != 1 ]; then
    echo "⚠️  ตอนนี้ใช้ Wayland อยู่ — ถ้าไม่มี linmo-wayland โหมดหน้าต่างแยกต้องใช้เซสชัน X11 (Xorg)"
fi
