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

echo "▶ ตั้งค่าเสียง…"
if ! modprobe snd-virtio 2>/dev/null; then
    if command -v apt-get >/dev/null 2>&1; then
        apt-get install -y -qq "linux-modules-extra-$(uname -r)" >/dev/null 2>&1 || true
        if dpkg -s linux-virtual >/dev/null 2>&1 && ! dpkg -s linux-generic >/dev/null 2>&1; then
            apt-get install -y -qq linux-generic >/dev/null 2>&1 || true
        fi
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y -q "kernel-modules-$(uname -r)" kernel-modules >/dev/null 2>&1 || true
    fi
    modprobe snd-virtio 2>/dev/null || true
fi
install -d /etc/modules-load.d
echo snd-virtio > /etc/modules-load.d/linmo-sound.conf
if ! command -v pipewire-pulse >/dev/null 2>&1 && ! command -v pulseaudio >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
        apt-get install -y -qq pipewire-audio wireplumber pipewire-pulse pipewire-alsa >/dev/null 2>&1 \
            || apt-get install -y -qq pulseaudio >/dev/null 2>&1 || true
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y -q pipewire-pulseaudio wireplumber pipewire-alsa >/dev/null 2>&1 || true
    elif command -v pacman >/dev/null 2>&1; then
        pacman -S --noconfirm --needed pipewire-pulse wireplumber pipewire-alsa >/dev/null 2>&1 || true
    fi
fi
if command -v pipewire-pulse >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1; then
    systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service >/dev/null 2>&1 || true
fi
if command -v xfce4-panel >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
    apt-get install -y -qq xfce4-pulseaudio-plugin pavucontrol >/dev/null 2>&1 || true
elif command -v xfce4-panel >/dev/null 2>&1 && command -v dnf >/dev/null 2>&1; then
    dnf install -y -q xfce4-pulseaudio-plugin pavucontrol >/dev/null 2>&1 || true
fi
if [ -d /sys/module/snd_virtio ]; then
    echo "  พบอุปกรณ์เสียงแล้ว"
else
    echo "  ยังโหลดไดรเวอร์เสียง snd-virtio ไม่ได้ — รีสตาร์ทเครื่องแล้วลองใหม่"
fi

echo "▶ ตั้งค่าโฟลเดอร์แชร์เพิ่มเติม…"
mkdir -p /mnt/linmo-extra
grep -q '^linmo-extra ' /etc/fstab || echo 'linmo-extra /mnt/linmo-extra virtiofs rw,nofail 0 0' >> /etc/fstab
mountpoint -q /mnt/linmo-extra || mount /mnt/linmo-extra 2>/dev/null || true

echo "▶ ตั้งค่าฮาร์ดดิสก์ภายนอกของ Mac…"
mkdir -p /mnt/linmo-drives
grep -q '^linmo-drives ' /etc/fstab || echo 'linmo-drives /mnt/linmo-drives virtiofs rw,nofail 0 0' >> /etc/fstab
mountpoint -q /mnt/linmo-drives || mount /mnt/linmo-drives 2>/dev/null || true
getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 { print $1 ":" $6 }' | while IFS=: read -r LINUX_USER LINUX_HOME; do
    [ -d "$LINUX_HOME" ] || continue
    for LINK in MacFolders:/mnt/linmo-extra MacDrives:/mnt/linmo-drives; do
        NAME="${LINK%%:*}"
        if [ ! -e "$LINUX_HOME/$NAME" ] && [ ! -L "$LINUX_HOME/$NAME" ]; then
            ln -s "${LINK#*:}" "$LINUX_HOME/$NAME"
            chown -h "$LINUX_USER:" "$LINUX_HOME/$NAME" 2>/dev/null || true
        fi
    done
    BOOKMARKS="$LINUX_HOME/.config/gtk-3.0/bookmarks"
    if [ ! -d "$LINUX_HOME/.config/gtk-3.0" ]; then
        mkdir -p "$LINUX_HOME/.config/gtk-3.0"
        chown "$LINUX_USER:" "$LINUX_HOME/.config" "$LINUX_HOME/.config/gtk-3.0" 2>/dev/null || true
    fi
    for NAME in MacDrives MacFolders; do
        if [ -e "$LINUX_HOME/$NAME" ] && ! grep -qs "^file://$LINUX_HOME/$NAME\( \|$\)" "$BOOKMARKS"; then
            echo "file://$LINUX_HOME/$NAME $NAME" >> "$BOOKMARKS"
        fi
    done
    [ -f "$BOOKMARKS" ] && chown "$LINUX_USER:" "$BOOKMARKS" 2>/dev/null || true
done
cat > /etc/udev/rules.d/90-linmo-hide-disks.rules <<'RULES'
ENV{ID_FS_LABEL}=="cidata|CIDATA|linmotools|LINMOTOOLS", ENV{UDISKS_IGNORE}="1"
RULES
udevadm control --reload 2>/dev/null || true
udevadm trigger --subsystem-match=block 2>/dev/null || true

echo "▶ ตั้งค่าส่งต่อพอร์ตและ SSH มาที่ Mac…"
install -m 0755 "$DIR/linmo-ports.py" /usr/local/lib/linmo/linmo-ports.py
if command -v apt-get >/dev/null 2>&1; then
    apt-get install -y -qq openssh-server >/dev/null 2>&1 || true
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y -q openssh-server >/dev/null 2>&1 || true
elif command -v pacman >/dev/null 2>&1; then
    pacman -S --noconfirm --needed openssh >/dev/null 2>&1 || true
fi
if [ -d /etc/ssh/sshd_config.d ]; then
    printf 'PasswordAuthentication yes\nKbdInteractiveAuthentication yes\n' > /etc/ssh/sshd_config.d/10-linmo.conf
fi
if command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now ssh >/dev/null 2>&1 || systemctl enable --now sshd >/dev/null 2>&1 || true
    systemctl reload ssh >/dev/null 2>&1 || systemctl reload sshd >/dev/null 2>&1 || true
    cat > /etc/systemd/system/linmo-ports.service <<'UNIT'
[Unit]
Description=LinMO: forward Linux ports to localhost on the Mac
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/lib/linmo/linmo-ports.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload || true
    systemctl enable linmo-ports.service >/dev/null 2>&1 || true
    systemctl restart linmo-ports.service >/dev/null 2>&1 || true
fi

echo "▶ ตั้งให้อัปเดต LinMO Tools เองทุกครั้งที่เปิดเครื่อง…"
cat > /usr/local/sbin/linmo-tools-update.new <<'UPDATER'
#!/bin/sh
MNT=/run/linmo-tools-update
mkdir -p "$MNT"
found=0
for d in /dev/vd? /dev/sr?; do
    [ -b "$d" ] || continue
    mount -o ro "$d" "$MNT" 2>/dev/null || continue
    if [ -e "$MNT/install.sh" ] && [ -e "$MNT/version.txt" ]; then
        found=1
        break
    fi
    umount "$MNT"
done
[ "$found" = 1 ] || exit 0
new="$(cat "$MNT/version.txt")"
old="$(cat /usr/local/lib/linmo/tools-version 2>/dev/null || true)"
status=0
if [ -n "$new" ] && [ "$new" != "$old" ]; then
    echo "LinMO Tools $old -> $new"
    LINMO_AUTO_UPDATE=1 sh "$MNT/install.sh" || status=$?
fi
umount "$MNT" 2>/dev/null || true
exit "$status"
UPDATER
chmod 0755 /usr/local/sbin/linmo-tools-update.new
mv -f /usr/local/sbin/linmo-tools-update.new /usr/local/sbin/linmo-tools-update
if command -v systemctl >/dev/null 2>&1; then
    cat > /etc/systemd/system/linmo-tools-update.service <<'UNIT'
[Unit]
Description=LinMO: update LinMO Tools from the attached tools disk
Wants=network-online.target
After=network-online.target local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/linmo-tools-update
TimeoutStartSec=20min

[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload || true
    systemctl enable linmo-tools-update.service >/dev/null 2>&1 || true
fi
if [ -f "$DIR/version.txt" ]; then
    install -m 0644 "$DIR/version.txt" /usr/local/lib/linmo/tools-version
fi

if [ "${LINMO_AUTO_UPDATE:-}" = 1 ]; then
    echo "✅ อัปเดต LinMO Tools แล้ว"
    exit 0
fi

echo "✅ ติดตั้งเสร็จแล้ว — ออกจากระบบแล้วเข้าใหม่ (หรือรีสตาร์ทเครื่อง) เพื่อเริ่มใช้งาน"
if [ "${XDG_SESSION_TYPE:-}" = "wayland" ] && [ "$WAYLAND_OK" != 1 ]; then
    echo "⚠️  ตอนนี้ใช้ Wayland อยู่ — ถ้าไม่มี linmo-wayland โหมดหน้าต่างแยกต้องใช้เซสชัน X11 (Xorg)"
fi
