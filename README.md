# LinMO — Linux on macOS

**[English](#english)** · **[ภาษาไทย](#ภาษาไทย)**

## English

The easiest way to use Linux on a Mac, with each Linux app opening in its own Mac window like a regular app.

> Status: **v0.11 (experimental)**. Linux apps show up in Launchpad, Spotlight and the "Linux Apps" menu bar menu.
> Ready-made software sets (Learn Linux / Developer / Security lab / Data science / Design), image copy and paste, and Mac App Store packaging.
> Suspend and resume, Linux ports and SSH from the Mac, Docker from the Mac, microphone, more shared folders, duplicate machines and one-click Wine.

The app's buttons and menus are in Thai. This README gives each Thai label followed by its English meaning, for example **หน้าต่างแยก** (Separate Windows).
The in-app guide (Help → LinMO Help, or Cmd + ?) is available in English and Thai.

### Features

- **Separate windows**: each Linux app opens in its own Mac window. Cmd+C / Cmd+V work, and apps open from the list in LinMO.
  - Smooth: only the changed parts of a window are sent
  - Sharp on Retina displays
  - Type Thai and other languages with the Mac keyboard and switch input sources the Mac way
  - Drag files from Finder into a Linux app (they are also saved to `~/Downloads/LinMO` in Linux)
  - Drag files out of a Linux app (such as the file manager) onto Finder or the Desktop
  - Type languages with composition (Japanese, Chinese, Korean); text being composed shows at the bottom corner of the window
  - Copy and paste text and images, including long text and large images
  - App icons in the app list, including SVG icons
- **Linux apps like Mac apps**: find them in Spotlight, open them from the Linux Apps menu in the menu bar, or add them to Launchpad.
  If the machine is off, LinMO starts it for you.
- **Software sets**: Learn Linux (man, vim, htop…), Developer (VS Code, Docker, Python, Node.js, Go, Java…),
  Security lab (nmap, Wireshark, John, hashcat, sqlmap…), Data science (JupyterLab, pandas, scikit-learn, R + tidyverse…),
  Design (GIMP, Inkscape, Krita, Blender, darktable, Scribus…)
- **One-click setup**: pick Debian 13, Ubuntu 24.04 or Fedora, set a user name and password, and wait. The app downloads, verifies and configures everything.
- **Choice of desktop**: XFCE (lightweight) or GNOME (Debian, Ubuntu)
- **First-boot progress**: a bar at the bottom of the screen shows the percentage and the current step
- **Thai ready**: Thai fonts, Thai keyboard (XFCE: Option + Shift, GNOME: Cmd + Space), optional Thai interface
- **Automatic login**: start the machine and go straight to the desktop
- **Shared folders**: a Mac folder appears at `~/Mac` in Linux. Add more folders at `~/MacFolders/<name>`, optionally read only.
  Changes made in Finder show up in the Linux file manager right away.
- **Suspend**: click **พักเครื่อง** (Suspend) and resume where you left off in seconds, with apps and open files intact
- **Snapshots**: save a machine's state and roll back in seconds. One-click machines get an automatic "หลังติดตั้งเสร็จ" (After setup) snapshot.
- **Duplicate a machine**: make a new machine identical to the original, using extra space only for what changes
- **Ports and SSH**: programs listening in Linux are reachable on the Mac at `localhost` on the same port, and SSH works at `localhost:2222` (next machines 2223, 2224…)
- **Docker from the Mac**: run `docker` on the Mac against Docker in Linux
- **Microphone**: let Linux use the Mac's microphone (turn it on in machine settings)
- **Rosetta**: run x86_64 Linux programs, turned on when creating a machine or later
- **Windows programs**: one-click Wine, either Hangover (32 and 64-bit) or WineHQ + Rosetta (64-bit, faster)
- **Self-updating LinMO Tools**: the agent in Linux updates to the version bundled with the app every time the machine starts
- **Multiple machines**: create as many machines as you like in one app
- **Install from your own file**: use any ARM64 distribution from an ISO or a `.img`, `.raw` or `.qcow2` disk image

### Requirements

- A Mac with Apple silicon (M1 or later)
- macOS 14 Sonoma or later
- Xcode 15 or later (or Command Line Tools with Swift 5.9+)
- An internet connection (for one-click setup)

### Build and run

```bash
git clone https://github.com/Little-Talk/LinMO---Mac-OS.git
cd LinMO---Mac-OS
./scripts/build-app.sh release --run
```

The app is built at `build/LinMO.app`. Drag it to Applications if you like.

> **Important:** clicking Run in Xcode can't start a machine, because the app needs the
> `com.apple.security.virtualization` entitlement. Use the script above, which signs it for you.

Test the App Store build (App Sandbox on) locally: `./scripts/build-app.sh sandbox --run`
To build for the Mac App Store, set `SIGN_IDENTITY`, `INSTALLER_IDENTITY`, `TEAM_ID` and `PROVISIONING_PROFILE`,
then run `./scripts/build-app.sh appstore`. You get `build/LinMO.pkg` to upload with Transporter.

### Usage

#### One-click setup (recommended)

1. Click **+** → choose **Debian**, **Ubuntu** or **Fedora** → **ถัดไป** (Next)
2. Pick a software set (Basic / Learn Linux / Developer / Security lab / Data science / Design) and a desktop (XFCE / GNOME),
   set a user name, password and Thai options → **ติดตั้ง** (Install)
3. Wait for the download (about 450–600 MB the first time; later machines reuse the cached file)
4. Click **เปิดเครื่อง** (Start). On first boot Linux installs the desktop and Thai support by itself, which takes about 10–30 minutes.
   Watch the progress bar at the bottom. When it finishes, the app restarts the machine into the desktop
   and saves a snapshot named **หลังติดตั้งเสร็จ** (After setup), so you can always go back to a fresh machine.

> Fedora offers XFCE only, because recent Fedora GNOME is Wayland-only, which can't share the clipboard with the Mac yet.

#### Separate-window mode

1. Start the machine and click **หน้าต่างแยก** (Separate Windows) in the toolbar
2. The Linux screen is replaced by an app list. Click an app and it opens as a Mac window
3. Windows already open in Linux appear as Mac windows too
4. Click **หน้าต่างแยก** (Separate Windows) again to go back to the full Linux desktop

Keyboard in this mode: **Cmd** acts as **Ctrl** (Cmd+C, Cmd+V, Cmd+S work like on a Mac),
Control-click is a right-click, and Cmd+Q still quits LinMO.
Text goes through the Mac input system, so you switch languages with the Mac's keys.
(Turn this off in machine settings → "พิมพ์ด้วยแป้นพิมพ์ของ Mac" (Type with the Mac keyboard) if you want Option to act as Alt.)

#### Linux apps in Spotlight, Launchpad and the menu bar

Every time a machine starts, LinMO remembers its apps so you can open them from anywhere on your Mac:

- **Spotlight**: press Cmd+Space and type a Linux app name (such as "Firefox" or "Terminal")
- **Linux Apps menu** (แอพ Linux): the grid icon in the menu bar, grouped by machine and category
- **Launchpad**: turn on LinMO → Settings… → "ใส่แอพ Linux ใน Launchpad" (Add Linux apps to Launchpad). Shortcuts live in `~/Applications/แอพ Linux (LinMO)`

If the machine is off, LinMO starts it and opens the app as a separate window once Linux is ready.
Turn each of these on or off in LinMO → Settings…

#### LinMO Agent and LinMO Tools

Machines created with the setup assistant since v0.4 already have LinMO Agent.
Once a machine has the self-updating LinMO Tools, Linux updates the agent to match the app on every boot, so you never rerun the command.

An orange arrow on **หน้าต่างแยก** (Separate Windows) means the machine still has an older agent that can't update itself.
Restart the machine, click the button, paste the command into a Linux Terminal, then log out and back in (once only).

Older machines and ISO installs: click **หน้าต่างแยก** (Separate Windows) and paste the install command into a Linux Terminal
(LinMO attaches the LinMO Tools disk to every machine), then log out and back in.

> This needs an X11 session (XFCE, or GNOME on Xorg as set up by LinMO). Wayland sessions use the mode below.

#### Wayland apps (experimental)

LinMO has its own Wayland compositor (**linmo-wayland**) that runs in the background in Linux.
Apps opened through it become Mac windows whether Linux uses X11 or Wayland.

- Turn it on: shut down → machine settings → **เปิดแอพผ่าน Wayland (ทดลอง)** (Open apps through Wayland (experimental))
- If Linux is Wayland-only (such as Fedora GNOME or Ubuntu 25.10+), LinMO uses linmo-wayland automatically
- Supports copy and paste (text and images), drag and drop in and out, window icons, menus, Thai/Japanese input, and X11 apps through Xwayland
- Supports `wp_viewporter` and fractional scaling, so apps like Firefox show at the right size on Retina displays and clicks land where you point
- X11 windows follow Mac window resizing and respect each app's minimum size
- Limits for X11 apps in this mode: images can't be copied from an X11 app to the Mac, and pastes from the Mac are limited to 64 KB
  (a Smithay 0.7 limit; X11 apps in the normal X11 agent mode don't have it)

The linmo-wayland binary for Linux ARM64 is built by GitHub Actions (`.github/workflows/linmo-wayland.yml`)
and committed to `guest/bin/`. If it's missing, Linux builds it from source during install (needs Rust 1.80+).

Test on any Linux machine: `python3 guest/tests/wayland_smoke.py guest/linmo-wayland/target/release/linmo-wayland`

#### Suspend

- While the machine runs, click **พักเครื่อง** (Suspend) in the toolbar. LinMO saves the machine's memory to a file and stops it
- Click **เปิดต่อ** (Resume) to return to where you were in a few seconds, with apps and open files intact
- If you quit LinMO while a machine is running, it offers **พักเครื่องแล้วปิดแอพ** (Suspend and Quit)
- While suspended you can't take snapshots, change settings, share folders or duplicate. Resume and shut down first,
  or choose **…** → **ทิ้งสถานะที่พักไว้…** (Discard Suspended State…), which is like pulling the plug: unsaved work is lost

#### Ports, SSH and Docker from the Mac

While the machine runs with a recent LinMO Tools, the **พอร์ต** (Ports) button in the toolbar lists Linux programs listening on a port,
with the name of each program (system ports are hidden).

- **Web**: for example run `python3 -m http.server 8000` in Linux, then open `http://localhost:8000` on the Mac or click it in the **พอร์ต** (Ports) menu
- **SSH**: LinMO installs OpenSSH and forwards port 22 to Mac port 2222 (the next machines get 2223, 2224…).
  Copy the command from **พอร์ต** (Ports) → **คัดลอกคำสั่ง SSH** (Copy SSH command), for example `ssh -p 2222 user@localhost`.
  Long-lived connections (such as VS Code Remote-SSH or large scp copies) stay connected
- **Docker**: if Linux has Docker (the Developer set includes it), LinMO opens a socket at `~/.linmo/<machine name>.sock` on the Mac.
  Choose **พอร์ต** (Ports) → **คัดลอกคำสั่งใช้ Docker ของ Linux จาก Mac** (Copy command to use Linux Docker from the Mac) and paste it into a Mac Terminal.
  It creates the docker context `linmo-<machine name>`, after which `docker ps` and `docker run` on the Mac talk to Docker in Linux
  (you need the `docker` command on the Mac, for example from `brew install docker`)

#### Microphone

Shut down → **…** → **ตั้งค่าเครื่อง…** (Machine Settings…) → turn on **ให้ Linux ใช้ไมโครโฟนของ Mac** (Let Linux use the Mac microphone), then allow access when macOS asks.
If you denied it before, turn it on in System Settings → Privacy & Security → Microphone.

#### More shared folders

Shut down → **…** → **โฟลเดอร์แชร์เพิ่มเติม…** (More Shared Folders…) → **เพิ่มโฟลเดอร์…** (Add Folder…).
Each folder appears at `~/MacFolders/<folder name>` in Linux. Tick **อ่านอย่างเดียว** (Read only) if you like. It takes effect on the next start,
and updates right away when files change in Finder, just like `~/Mac`.

#### Duplicate a machine

Shut down → **…** → **ทำสำเนาเครื่อง** (Duplicate Machine). You get "<name> (สำเนา)" with everything the original has.
Duplicates use an APFS clone, so they're quick and only use extra space for what changes.

> A duplicate shares the original's network card (MAC address), so the two can't run at the same time. Shut one down first.

#### Windows programs (Wine)

Start the machine (Debian or Ubuntu) → click **Wine** → pick a flavor → **คัดลอกคำสั่ง** (Copy Command) and paste it into a Linux Terminal.

- **Hangover**: runs both 32-bit and 64-bit Windows programs without Rosetta. Recommended for most programs
- **WineHQ + Rosetta**: faster, but only runs 64-bit programs and needs Rosetta turned on first
  (Rosetta translates x86_64 only, not i386, so LinMO installs the amd64 WineHQ)

When it's done, double-click a `.exe` / `.msi` file or run `wine program.exe`. Only one flavor can be installed at a time; installing one removes the other.

#### Install from an ISO or disk image

1. Click **+** → **ติดตั้งเองจากไฟล์ ISO หรือ IMG** (Install from ISO or IMG file) → pick an **ARM64 / aarch64** file
   - `.iso`: used as an installer disc
   - `.img` / `.raw`: use it as an installer (like a live USB) or as the machine's disk that boots right away (such as an Armbian image)
   - `.qcow2`: converted into the machine's disk and boots right away
   The original file is never changed. The machine's disk is grown to the size you set.
2. Start the machine. If the file is an installer, follow the distribution's installer
3. When done, shut down, click **ถอดแผ่นติดตั้ง** (Eject Installer), and start again

These machines need LinMO Tools installed by hand (see LinMO Agent above), and may need some setup in Linux:

```bash
# clipboard
sudo apt install spice-vdagent        # or: sudo dnf install spice-vdagent

# shared folder (choose the folder in the app first)
sudo mkdir -p /mnt/linmo
echo 'linmo /mnt/linmo virtiofs rw,nofail 0 0' | sudo tee -a /etc/fstab
sudo mount -a
```

#### Rosetta (turning it on later)

Rosetta runs x86_64 Linux programs, but not 32-bit (i386) programs.

1. Shut down → **…** → **ตั้งค่าเครื่อง…** (Machine Settings…) → turn on **รันโปรแกรม x86_64 ผ่าน Rosetta** (Run x86_64 programs with Rosetta). LinMO installs Rosetta on the Mac if it's missing
2. Start the machine again
3. Run the LinMO Tools install command in a Linux Terminal again. LinMO Tools mounts Rosetta and registers binfmt for you

### Where files are stored

| Location | What it is |
|---|---|
| `~/Library/Application Support/LinMO/Machines/<id>.vmbundle/` | Each machine (disk, NVRAM, config, snapshots, suspended state `SavedState.vzvmsave`, lock file `Machine.lock`) |
| `~/.linmo/<machine name>.sock` | Socket for using Linux Docker from the Mac (only while the machine runs) |
| `~/Library/Caches/LinMO/` | Downloaded Linux images. See their size and delete them in **LinMO → Settings…** |
| `~/Library/Application Support/LinMO/LinuxApps.json` | Remembered Linux apps (for Spotlight, the menu and Launchpad) |
| `~/Applications/แอพ Linux (LinMO)/` | Launchpad shortcuts for Linux apps (if turned on) |

The Mac App Store build (App Sandbox) keeps everything in `~/Library/Containers/io.github.jeerapatsepu.LinMO/` instead.

Machines from v0.1 are moved to the new location automatically.

### Code layout

```
Sources/LinMO/
├── LinMOApp.swift
├── Model/
│   ├── MachineConfig.swift        machine settings, snapshots
│   ├── MachineBundle.swift        machine files, create/delete/duplicate, APFS-clone snapshots
│   ├── MachineLock.swift          stops two LinMO apps from opening the same disk
│   └── SecurityScopedBookmark.swift  access to user-chosen files and folders (App Sandbox)
├── Launcher/
│   ├── LinuxAppCatalog.swift      Linux apps from every machine + Spotlight
│   └── LaunchpadShortcuts.swift   Launchpad shortcuts + opening apps from linmo://launch
├── VM/
│   ├── ConfigurationBuilder.swift Virtualization.framework configuration, Rosetta
│   ├── MachineController.swift    start/stop/suspend, settings, snapshots
│   ├── PortForwarder.swift        forwards Linux ports, SSH and Docker to the Mac
│   ├── SharedFolderWatcher.swift  tells Linux when shared-folder files change
│   ├── SetupProgressListener.swift receives setup progress from Linux over vsock
│   └── MachineLibrary.swift       machine list, migration from v0.1
├── Seamless/                      separate-window mode: connection, Mac windows, key mapping
├── Guest/                         agent files embedded in the app + LinMO Tools disk
├── Provisioning/
│   ├── DistroCatalog.swift        distributions and desktops available for one-click setup
│   ├── ImageStore.swift           URL lookup, download, checksum, cache
│   ├── DiskConverters.swift       converts qcow2 / xz / img to sparse raw disks
│   ├── CloudInit.swift            per-distribution setup recipes + progress reporter
│   ├── Presets.swift              software sets: Learn Linux / Developer / Security lab / Data science / Design
│   └── Provisioner.swift          one-click machine creation steps
└── UI/                            all screens (SwiftUI)
guest/                             LinMO Agent (Python), linmo-ports.py and the Linux install script
guest/linmo-wayland/               LinMO's Wayland compositor (Rust + Smithay)
guest/tests/                       tests for the agent and linmo-wayland with real apps
scripts/                           app build and guest file embedding
```

### Troubleshooting

- **"The process doesn't have the com.apple.security.virtualization entitlement"**
  → open the `build/LinMO.app` made by the script, not Run in Xcode
- **One-click setup takes a long time** → the first time usually takes 10–30 minutes depending on your connection. Check the latest step in the bottom bar.
  If the number doesn't move for over 20 minutes, check your internet and restart the machine
- **The bar reports a failed step** → open a Terminal in Linux and check `sudo less /var/log/cloud-init-output.log`
- **ISO won't boot / black screen** → make sure the ISO is ARM64, not x86_64 (amd64)
- **Boots into the installer every time** → shut down and click "ถอดแผ่นติดตั้ง" (Eject Installer)
- **Can't write to ~/Mac** → ISO installs may have a uid that doesn't match the Mac. Use `sudo`, or set the uid to match `id -u` on the Mac
- **Stuck on a text console after first-boot setup** → click **ปิดเครื่อง** (Shut Down); the app restarts the machine into the desktop
- **No internet in Linux** → machines created before v0.10 may need a one-time netplan change that matches the network card by driver `virtio_net` instead of MAC address
- **"เครื่องนี้กำลังถูกใช้อยู่ในแอพ LinMO อีกตัวหนึ่ง" (this machine is in use by another LinMO app)** → two copies of LinMO (such as one in `build/` and one in Applications) are using the same machine.
  Shut it down or quit the other copy first. LinMO blocks this because running the same disk twice corrupts it
- **"เป็นต้นฉบับหรือสำเนาของเครื่องนี้และเปิดอยู่" (the original or a duplicate is running)** → shut down the running original or duplicate first, because both use the same network card
- **No Ports button / SSH doesn't work** → update LinMO Tools (see LinMO Agent) and restart the machine
- **Snapshot button is disabled** → the machine is suspended. Click **เปิดต่อ** (Resume), then shut down

## ภาษาไทย

ใช้ Linux บน Mac แบบง่ายที่สุด และเปิดแอพ Linux เป็นหน้าต่างแยกบน Mac เหมือนแอพปกติ

> สถานะ: **v0.11 (เวอร์ชันทดลอง)** — แอพ Linux อยู่ใน Launchpad, Spotlight และเมนู "แอพ Linux" บนแถบเมนู,
> ชุดสำเร็จรูป (สายเรียน Linux / สาย dev / สาย security lab / สาย data science / สายออกแบบ), copy-paste รูปภาพ และเตรียมพร้อมส่งขึ้น Mac App Store
> พักเครื่องแล้วกลับมาที่เดิม, ใช้พอร์ตและ SSH ของ Linux จาก Mac, Docker จาก Mac, ไมโครโฟน, แชร์หลายโฟลเดอร์, ทำสำเนาเครื่อง และติดตั้ง Wine คลิกเดียว

### ฟีเจอร์

- **หน้าต่างแยก** — แอพ Linux แต่ละตัวเปิดเป็นหน้าต่างของตัวเองบน Mac ใช้ Cmd+C / Cmd+V ได้ เปิดแอพได้จากรายการในแอพ LinMO
  - ลื่น: ส่งเฉพาะส่วนของหน้าต่างที่เปลี่ยน
  - คมชัดบนจอ Retina
  - พิมพ์ไทยด้วยแป้นพิมพ์ของ Mac ได้เลย (สลับภาษาแบบ Mac)
  - ลากไฟล์จาก Finder ไปวางในแอพ Linux ได้ (ไฟล์อยู่ที่ `~/Downloads/LinMO` ใน Linux ด้วย)
  - ลากไฟล์จากแอพ Linux (เช่น file manager) ออกมาวางที่ Finder หรือ Desktop ได้
  - พิมพ์ภาษาที่มีการเลือกคำ (ญี่ปุ่น จีน เกาหลี) ได้ ข้อความที่กำลังพิมพ์จะแสดงที่มุมล่างของหน้าต่าง
  - copy-paste ได้ทั้งข้อความและรูปภาพ (ข้อความยาวและรูปใหญ่ก็ได้)
  - ไอคอนแอพในรายการแอพ (รวมไอคอนแบบ SVG)
- **แอพ Linux เหมือนแอพ Mac** — ค้นหาใน Spotlight, เปิดจากเมนู "แอพ Linux" บนแถบเมนู หรือใส่ไว้ใน Launchpad
  เลือกแอพแล้ว LinMO เปิดเครื่องให้เองถ้ายังปิดอยู่
- **ชุดสำเร็จรูป** — ติดตั้งโปรแกรมตามสาย: เรียน Linux (man, vim, htop…), dev (VS Code, Docker, Python, Node.js, Go, Java…),
  security lab (nmap, Wireshark, John, hashcat, sqlmap…), data science (JupyterLab, pandas, scikit-learn, R + tidyverse…),
  ออกแบบ (GIMP, Inkscape, Krita, Blender, darktable, Scribus…)
- **ติดตั้งคลิกเดียว** — เลือก Debian 13, Ubuntu 24.04 หรือ Fedora ตั้งชื่อผู้ใช้/รหัสผ่าน แล้วรอ แอพดาวน์โหลด ตรวจสอบไฟล์ และตั้งค่าให้ทั้งหมด
- **เลือกหน้าจอได้** — XFCE (เบา) หรือ GNOME (Debian, Ubuntu)
- **ดูความคืบหน้าการตั้งค่าครั้งแรก** — แถบด้านล่างหน้าจอบอกเปอร์เซ็นต์และขั้นตอนที่กำลังทำ
- **ภาษาไทยพร้อมใช้** — ฟอนต์ไทย, คีย์บอร์ดไทย (XFCE: Option + Shift, GNOME: Cmd + Space), เลือกเมนูไทยได้
- **เข้าระบบอัตโนมัติ** — เปิดเครื่องแล้วเข้าหน้าจอ desktop เลย
- **แชร์โฟลเดอร์** — โฟลเดอร์จาก Mac โผล่ที่ `~/Mac` ใน Linux อัตโนมัติ เพิ่มโฟลเดอร์อื่นได้อีกที่ `~/MacFolders/<ชื่อ>`
  (เลือกอ่านอย่างเดียวได้) เปลี่ยนไฟล์ใน Finder แล้วตัวจัดการไฟล์ใน Linux อัปเดตทันที
- **แชร์ clipboard** — copy บน Mac แล้ว paste ใน Linux ได้ (และกลับกัน)
- **พักเครื่อง** — กด **พักเครื่อง** แล้วเปิดต่อได้ที่เดิมในไม่กี่วินาที ทั้งแอพและไฟล์ที่เปิดค้างไว้
- **Snapshot** — บันทึกสถานะเครื่อง ทำพังแล้วย้อนกลับได้ในไม่กี่วินาที เครื่องแบบคลิกเดียวมี snapshot "หลังติดตั้งเสร็จ" ให้อัตโนมัติ
- **ทำสำเนาเครื่อง** — สร้างเครื่องใหม่ที่เหมือนเดิมทุกอย่าง ใช้พื้นที่เพิ่มเฉพาะส่วนที่ต่างกัน
- **พอร์ตและ SSH** — โปรแกรมที่เปิดพอร์ตใน Linux ใช้จาก Mac ได้ที่ `localhost` พอร์ตเดียวกัน และ SSH เข้า Linux ได้ที่ `localhost:2222` (เครื่องถัดไป 2223, 2224…)
- **Docker จาก Mac** — สั่ง `docker` บน Mac ให้ทำงานกับ Docker ใน Linux ได้
- **ไมโครโฟน** — ให้ Linux ใช้ไมโครโฟนของ Mac ได้ (เปิดในตั้งค่าเครื่อง)
- **Rosetta** — รันโปรแกรม Linux แบบ x86_64 ได้ เปิดตอนสร้างเครื่องหรือเปิดทีหลังก็ได้
- **โปรแกรม Windows** — ติดตั้ง Wine คลิกเดียว เลือก Hangover (32 และ 64 บิต) หรือ WineHQ + Rosetta (64 บิต เร็วกว่า)
- **LinMO Tools อัปเดตเอง** — เปิดเครื่องแล้ว agent ใน Linux อัปเดตเป็นรุ่นที่มากับแอพให้เอง
- **หลายเครื่อง** — สร้างได้หลายเครื่องในแอพเดียว
- **ติดตั้งเองจากไฟล์** — ใช้ distro อื่นที่เป็น ARM64 ได้ จากไฟล์ ISO หรือไฟล์ดิสก์ `.img`, `.raw`, `.qcow2`

### สิ่งที่ต้องมี

- Mac ชิป Apple (M1 ขึ้นไป)
- macOS 14 Sonoma ขึ้นไป
- Xcode 15 ขึ้นไป (หรือ Command Line Tools ที่มี Swift 5.9+)
- อินเทอร์เน็ต (สำหรับติดตั้งแบบคลิกเดียว)

### วิธี build และเปิดแอพ

```bash
git clone https://github.com/Little-Talk/LinMO---Mac-OS.git
cd LinMO---Mac-OS
./scripts/build-app.sh release --run
```

แอพจะอยู่ที่ `build/LinMO.app` ลากไปไว้ใน Applications ได้เลย

> **สำคัญ:** การกด Run ใน Xcode ตรงๆ จะเปิดเครื่องไม่ได้ เพราะแอพต้องมีสิทธิ์
> `com.apple.security.virtualization` ให้ใช้สคริปต์ด้านบน ซึ่งเซ็นสิทธิ์ให้อัตโนมัติ

ทดสอบรุ่น App Store (เปิด App Sandbox) บนเครื่องตัวเอง: `./scripts/build-app.sh sandbox --run`
build รุ่นส่งขึ้น Mac App Store: ตั้งตัวแปร `SIGN_IDENTITY`, `INSTALLER_IDENTITY`, `TEAM_ID` และ `PROVISIONING_PROFILE`
แล้วสั่ง `./scripts/build-app.sh appstore` จะได้ `build/LinMO.pkg` ไว้อัปโหลดด้วย Transporter

### วิธีใช้งาน

#### แบบคลิกเดียว (แนะนำ)

1. กด **+** → เลือก **Debian**, **Ubuntu** หรือ **Fedora** → ถัดไป
2. เลือกชุดโปรแกรม (พื้นฐาน / สายเรียน Linux / สาย dev / สาย security lab / สาย data science / สายออกแบบ) หน้าจอ (XFCE / GNOME)
   ตั้งชื่อผู้ใช้ รหัสผ่าน และตัวเลือกภาษาไทย → **ติดตั้ง**
3. รอดาวน์โหลด (ครั้งแรกประมาณ 450–600 MB ครั้งต่อไปใช้ไฟล์เดิมได้ทันที)
4. กด **เปิดเครื่อง** — ครั้งแรก Linux จะติดตั้งหน้าจอและภาษาไทยเอง ใช้เวลาประมาณ 10–30 นาที
   ดูความคืบหน้าได้ที่แถบด้านล่างของหน้าจอ เมื่อเสร็จแอพจะเปิดเครื่องใหม่เข้าหน้าจอ desktop ให้เอง
   และบันทึก snapshot ชื่อ **หลังติดตั้งเสร็จ** ไว้ให้ ย้อนกลับมาเป็นเครื่องใหม่เอี่ยมได้ทุกเมื่อ

> Fedora มีให้เฉพาะ XFCE เพราะ GNOME ของ Fedora รุ่นใหม่ใช้ Wayland อย่างเดียว ซึ่งยังแชร์ clipboard กับ Mac ไม่ได้

#### โหมดหน้าต่างแยก

1. เปิดเครื่อง แล้วกดปุ่ม **หน้าต่างแยก** ที่แถบด้านบน
2. หน้าจอ Linux จะถูกแทนด้วยรายการแอพ — คลิกแอพที่ต้องการ แอพจะเปิดเป็นหน้าต่าง Mac
3. หน้าต่างที่เปิดอยู่แล้วใน Linux จะโผล่มาเป็นหน้าต่าง Mac ด้วย
4. กดปุ่ม **หน้าต่างแยก** อีกครั้งเพื่อกลับไปดูหน้าจอ Linux ทั้งจอ

คีย์บอร์ดในโหมดนี้: **Cmd** ทำหน้าที่เป็น **Ctrl** (Cmd+C, Cmd+V, Cmd+S ใช้ได้เหมือนบน Mac),
Control+คลิก = คลิกขวา, Cmd+Q ยังเป็นการปิดแอพ LinMO
ตัวอักษรพิมพ์ผ่านระบบพิมพ์ของ Mac จึงสลับไทย/อังกฤษด้วยปุ่มของ Mac ได้เลย
(ปิดได้ที่ ตั้งค่าเครื่อง → "พิมพ์ด้วยแป้นพิมพ์ของ Mac" ถ้าต้องการให้ Option เป็น Alt)

#### แอพ Linux ใน Spotlight, Launchpad และแถบเมนู

ทุกครั้งที่เปิดเครื่อง LinMO จะจำรายการแอพของเครื่องนั้นไว้ แล้วให้เปิดแอพได้จากทุกที่บน Mac:

- **Spotlight** — กด Cmd+Space พิมพ์ชื่อแอพ Linux (เช่น "Firefox", "Terminal")
- **เมนู "แอพ Linux"** — ไอคอนตารางบนแถบเมนู แยกตามเครื่องและหมวดหมู่
- **Launchpad** — เปิดที่ LinMO → Settings… → "ใส่แอพ Linux ใน Launchpad" (ทางลัดอยู่ที่ `~/Applications/แอพ Linux (LinMO)`)

ถ้าเครื่องยังปิดอยู่ LinMO จะเปิดเครื่องให้ แล้วเปิดแอพเป็นหน้าต่างแยกเมื่อ Linux พร้อม
ปิด/เปิดแต่ละอย่างได้ที่ LinMO → Settings…

#### LinMO Agent และ LinMO Tools

เครื่องที่สร้างด้วยตัวช่วยติดตั้งตั้งแต่ v0.4 มี LinMO Agent ให้แล้ว
และตั้งแต่ติดตั้ง LinMO Tools รุ่นที่อัปเดตเองได้ ทุกครั้งที่เปิดเครื่อง Linux จะอัปเดต agent ให้ตรงกับแอพเอง ไม่ต้องรันคำสั่งซ้ำ

ถ้าแอพขึ้นลูกศรสีส้มที่ปุ่ม **หน้าต่างแยก** แปลว่าเครื่องนั้นยังเป็น agent รุ่นเก่าที่อัปเดตเองไม่ได้
ให้รีสตาร์ตเครื่อง คลิกปุ่ม แล้วคัดลอกคำสั่งไปวางใน Terminal ของ Linux จากนั้นออกจากระบบแล้วเข้าใหม่ (ทำครั้งเดียว)

เครื่องที่สร้างก่อนหน้านั้นหรือติดตั้งจาก ISO: กดปุ่ม **หน้าต่างแยก** แล้วคัดลอกคำสั่งติดตั้งไปวางใน Terminal ของ Linux
(แอพต่อแผ่น LinMO Tools ให้ทุกเครื่องอยู่แล้ว) จากนั้นออกจากระบบแล้วเข้าใหม่

> ต้องใช้หน้าจอแบบ X11 (XFCE หรือ GNOME on Xorg ที่ LinMO ตั้งให้) — ยังไม่รองรับเซสชัน Wayland

#### แอพ Wayland (ทดลอง)

LinMO มี compositor Wayland ของตัวเอง (**linmo-wayland**) ที่ทำงานเบื้องหลังใน Linux
แอพที่เปิดผ่านมันจะเป็นหน้าต่าง Mac ได้เลย ไม่ว่า Linux จะใช้ X11 หรือ Wayland

- เปิดใช้: ปิดเครื่อง → ตั้งค่าเครื่อง → **เปิดแอพผ่าน Wayland (ทดลอง)**
- ถ้า Linux ใช้ Wayland อย่างเดียว (เช่น Fedora GNOME, Ubuntu 25.10+) LinMO จะใช้ linmo-wayland ให้อัตโนมัติ
- รองรับ copy-paste (ข้อความ + รูปภาพ), ลากไฟล์เข้า/ออก, ไอคอนหน้าต่าง, เมนู, พิมพ์ไทย/ญี่ปุ่น และแอพ X11 ผ่าน Xwayland
- รองรับ `wp_viewporter` และ fractional scale แอพอย่าง Firefox จึงแสดงขนาดถูกต้องบนจอ Retina และคลิกตรงตำแหน่ง
- หน้าต่าง X11 ปรับขนาดตามหน้าต่าง Mac และเคารพขนาดเล็กสุดของแอพ
- ข้อจำกัดของแอพ X11 ในโหมดนี้: copy รูปจากแอพ X11 ไป Mac ไม่ได้ และ paste จาก Mac ได้ไม่เกิน 64 KB ต่อครั้ง
  (ข้อจำกัดของ Smithay 0.7 — แอพ X11 ในโหมด X11 agent ปกติไม่มีข้อจำกัดนี้)

ไฟล์ของ linmo-wayland สำหรับ Linux ARM64 สร้างโดย GitHub Actions (`.github/workflows/linmo-wayland.yml`)
แล้ว commit ไว้ที่ `guest/bin/` — ถ้ายังไม่มี เครื่อง Linux จะสร้างจากซอร์สโค้ดเองตอนติดตั้ง (ต้องมี Rust 1.80+)

ทดสอบบนเครื่อง Linux ใดก็ได้: `python3 guest/tests/wayland_smoke.py guest/linmo-wayland/target/release/linmo-wayland`

#### พักเครื่อง (suspend)

- ขณะเครื่องเปิดอยู่ กด **พักเครื่อง** ที่แถบด้านบน LinMO เก็บหน่วยความจำของเครื่องไว้ในไฟล์ แล้วปิดเครื่อง
- กด **เปิดต่อ** เพื่อกลับมาที่เดิมในไม่กี่วินาที ทั้งแอพและไฟล์ที่เปิดค้างไว้
- ปิดแอพ LinMO ขณะเครื่องเปิดอยู่ แอพจะถามว่าจะ **พักเครื่องแล้วปิดแอพ** หรือไม่
- ระหว่างพักอยู่ ทำ snapshot, ตั้งค่าเครื่อง, แชร์โฟลเดอร์ และทำสำเนาไม่ได้ ให้เปิดต่อแล้วปิดเครื่องก่อน
  หรือเลือก **…** → **ทิ้งสถานะที่พักไว้…** (เหมือนถอดปลั๊ก งานที่ยังไม่บันทึกจะหาย)

#### พอร์ต, SSH และ Docker จาก Mac

เมื่อเครื่องเปิดอยู่และมี LinMO Tools รุ่นใหม่ ปุ่ม **พอร์ต** ที่แถบด้านบนจะแสดงโปรแกรมใน Linux ที่เปิดพอร์ตรอรับการเชื่อมต่อ
พร้อมชื่อโปรแกรม (ซ่อนพอร์ตของระบบให้แล้ว)

- **เว็บ** — เช่นรัน `python3 -m http.server 8000` ใน Linux แล้วเปิด `http://localhost:8000` บน Mac หรือคลิกจากเมนู **พอร์ต**
- **SSH** — LinMO ติดตั้ง OpenSSH ให้ และส่งพอร์ต 22 มาที่ Mac พอร์ต 2222 (เครื่องถัดไปได้ 2223, 2224…)
  คัดลอกคำสั่งจากเมนู **พอร์ต** → **คัดลอกคำสั่ง SSH** เช่น `ssh -p 2222 ชื่อผู้ใช้@localhost`
  ใช้การเชื่อมต่อนานๆ (เช่น VS Code Remote-SSH, scp ไฟล์ใหญ่) ได้โดยไม่หลุด
- **Docker** — ถ้าใน Linux มี Docker (เช่นชุดสาย dev) LinMO จะเปิด socket ไว้ที่ `~/.linmo/<ชื่อเครื่อง>.sock` บน Mac
  เลือก **พอร์ต** → **คัดลอกคำสั่งใช้ Docker ของ Linux จาก Mac** แล้ววางใน Terminal ของ Mac
  คำสั่งนี้สร้าง docker context `linmo-<ชื่อเครื่อง>` จากนั้น `docker ps`, `docker run` บน Mac จะทำงานกับ Docker ใน Linux
  (ต้องมีคำสั่ง `docker` บน Mac เช่นจาก `brew install docker`)

#### ไมโครโฟน

ปิดเครื่อง → **…** → **ตั้งค่าเครื่อง…** → เปิด **ให้ Linux ใช้ไมโครโฟนของ Mac** แล้วอนุญาตเมื่อ macOS ถาม
ถ้าเคยกดไม่อนุญาต เปิดได้ที่ System Settings → Privacy & Security → Microphone

#### แชร์โฟลเดอร์เพิ่มเติม

ปิดเครื่อง → **…** → **โฟลเดอร์แชร์เพิ่มเติม…** → **เพิ่มโฟลเดอร์…**
แต่ละโฟลเดอร์จะอยู่ที่ `~/MacFolders/<ชื่อโฟลเดอร์>` ใน Linux เลือก **อ่านอย่างเดียว** ได้ มีผลเมื่อเปิดเครื่องครั้งถัดไป
และอัปเดตทันทีเมื่อไฟล์ใน Finder เปลี่ยนเหมือน `~/Mac`

#### ทำสำเนาเครื่อง

ปิดเครื่อง → **…** → **ทำสำเนาเครื่อง** จะได้เครื่อง "<ชื่อ> (สำเนา)" ที่มีทุกอย่างเหมือนเดิม
สำเนาใช้ APFS clone จึงเสร็จเร็วและใช้พื้นที่เพิ่มเฉพาะส่วนที่ต่างกัน

> สำเนาใช้การ์ดเครือข่าย (MAC address) เดียวกับต้นฉบับ จึงเปิดพร้อมกันไม่ได้ ต้องปิดเครื่องหนึ่งก่อน

#### โปรแกรม Windows (Wine)

เปิดเครื่อง (Debian หรือ Ubuntu) → กดปุ่ม **Wine** → เลือกแบบ → **คัดลอกคำสั่ง** แล้ววางใน Terminal ของ Linux

- **Hangover** — เปิดโปรแกรม Windows ได้ทั้ง 32 และ 64 บิต ไม่ต้องใช้ Rosetta แนะนำสำหรับโปรแกรมส่วนใหญ่
- **WineHQ + Rosetta** — เร็วกว่า แต่เปิดได้เฉพาะโปรแกรม 64 บิต และต้องเปิด Rosetta ก่อน
  (Rosetta แปลได้เฉพาะ x86_64 ไม่รองรับ i386 LinMO จึงติดตั้ง WineHQ รุ่น amd64)

ติดตั้งเสร็จแล้วดับเบิลคลิกไฟล์ `.exe` / `.msi` หรือสั่ง `wine โปรแกรม.exe` ติดตั้งได้ทีละแบบ ลงแบบหนึ่งแล้วอีกแบบจะถูกถอดออก

#### ติดตั้งเองจากไฟล์ ISO หรือดิสก์

1. กด **+** → **ติดตั้งเองจากไฟล์ ISO หรือ IMG** → เลือกไฟล์รุ่น **ARM64 / aarch64**
   - `.iso` — ใช้เป็นแผ่นติดตั้ง
   - `.img` / `.raw` — เลือกได้ว่าจะใช้เป็นแผ่นติดตั้ง (live USB) หรือเป็นดิสก์ของเครื่องที่บูตได้เลย (เช่นไฟล์ของ Armbian)
   - `.qcow2` — แปลงเป็นดิสก์ของเครื่องแล้วบูตได้เลย
   ไฟล์ต้นฉบับไม่ถูกแก้ ดิสก์ของเครื่องจะถูกขยายเป็นขนาดที่ตั้งไว้
2. เปิดเครื่อง ถ้าเป็นแผ่นติดตั้ง ให้ติดตั้งตามขั้นตอนของ distro
3. ติดตั้งเสร็จ ปิดเครื่อง กด **ถอดแผ่นติดตั้ง** แล้วเปิดใหม่

เครื่องแบบนี้ต้องติดตั้ง LinMO Tools เอง (ดูหัวข้อ LinMO Agent ด้านบน) และอาจต้องตั้งค่าบางอย่างใน Linux เอง:

```bash
# clipboard
sudo apt install spice-vdagent        # หรือ: sudo dnf install spice-vdagent

# โฟลเดอร์แชร์ (ตั้งโฟลเดอร์ในแอพก่อน)
sudo mkdir -p /mnt/linmo
echo 'linmo /mnt/linmo virtiofs rw,nofail 0 0' | sudo tee -a /etc/fstab
sudo mount -a
```

#### Rosetta (เปิดใช้ทีหลัง)

Rosetta รันโปรแกรม Linux แบบ x86_64 ได้ แต่ไม่รองรับโปรแกรม 32 บิต (i386)

1. ปิดเครื่อง → **…** → **ตั้งค่าเครื่อง…** → เปิด **รันโปรแกรม x86_64 ผ่าน Rosetta** (แอพจะติดตั้ง Rosetta ให้ Mac ถ้ายังไม่มี)
2. เปิดเครื่องใหม่
3. รันคำสั่งติดตั้ง LinMO Tools ใน Terminal ของ Linux อีกครั้ง LinMO Tools จะ mount Rosetta และลงทะเบียน binfmt ให้เอง

### ไฟล์เก็บไว้ที่ไหน

| ที่อยู่ | คืออะไร |
|---|---|
| `~/Library/Application Support/LinMO/Machines/<id>.vmbundle/` | เครื่องแต่ละเครื่อง (ดิสก์, NVRAM, config, snapshot, สถานะที่พักไว้ `SavedState.vzvmsave`, ไฟล์ล็อก `Machine.lock`) |
| `~/.linmo/<ชื่อเครื่อง>.sock` | socket สำหรับใช้ Docker ของ Linux จาก Mac (มีเฉพาะตอนเครื่องเปิดอยู่) |
| `~/Library/Caches/LinMO/` | ไฟล์ Linux ที่ดาวน์โหลดไว้ ดูขนาดและลบได้ที่ **LinMO → Settings…** |
| `~/Library/Application Support/LinMO/LinuxApps.json` | รายการแอพ Linux ที่จำไว้ (สำหรับ Spotlight, เมนู และ Launchpad) |
| `~/Applications/แอพ Linux (LinMO)/` | ทางลัดของแอพ Linux ใน Launchpad (ถ้าเปิดใช้) |

รุ่น Mac App Store (App Sandbox) เก็บทุกอย่างใน `~/Library/Containers/io.github.jeerapatsepu.LinMO/` แทน

เครื่องจาก v0.1 จะถูกย้ายมาที่ใหม่ให้อัตโนมัติ

### โครงสร้างโค้ด

```
Sources/LinMO/
├── LinMOApp.swift
├── Model/
│   ├── MachineConfig.swift        การตั้งค่าเครื่อง, Snapshot
│   ├── MachineBundle.swift        ไฟล์ของเครื่อง, สร้าง/ลบ/ทำสำเนา, snapshot ด้วย APFS clone
│   ├── MachineLock.swift          ล็อกเครื่องไม่ให้แอพสองตัวเปิดดิสก์เดียวกัน
│   └── SecurityScopedBookmark.swift  สิทธิ์ไฟล์/โฟลเดอร์ที่ผู้ใช้เลือก (App Sandbox)
├── Launcher/
│   ├── LinuxAppCatalog.swift      รายการแอพ Linux ทุกเครื่อง + Spotlight
│   └── LaunchpadShortcuts.swift   ทางลัดใน Launchpad + เปิดแอพจาก linmo://launch
├── VM/
│   ├── ConfigurationBuilder.swift สร้าง config ของ Virtualization.framework, Rosetta
│   ├── MachineController.swift    เปิด/ปิด/พักเครื่อง, ตั้งค่า, snapshot
│   ├── PortForwarder.swift        ส่งพอร์ต, SSH และ Docker ของ Linux มาที่ Mac
│   ├── SharedFolderWatcher.swift  แจ้ง Linux เมื่อไฟล์ในโฟลเดอร์แชร์เปลี่ยน
│   ├── SetupProgressListener.swift รับความคืบหน้าจาก Linux ผ่าน vsock
│   └── MachineLibrary.swift       รายการเครื่อง, ย้ายข้อมูลจาก v0.1
├── Seamless/                      โหมดหน้าต่างแยก: การเชื่อมต่อ, หน้าต่าง Mac, แปลงปุ่มคีย์บอร์ด
├── Guest/                         ไฟล์ของ agent ที่ฝังในแอพ + สร้างแผ่น LinMO Tools
├── Provisioning/
│   ├── DistroCatalog.swift        รายการ distro และหน้าจอ desktop ที่ติดตั้งคลิกเดียวได้
│   ├── ImageStore.swift           หา URL, ดาวน์โหลด, ตรวจ checksum, แคช
│   ├── DiskConverters.swift       แปลง qcow2 / xz / img เป็นดิสก์ raw แบบ sparse
│   ├── CloudInit.swift            สูตรตั้งค่าแต่ละ distro + สคริปต์รายงานความคืบหน้า
│   ├── Presets.swift              ชุดสำเร็จรูป: สายเรียน Linux / dev / security lab / data science / ออกแบบ
│   └── Provisioner.swift          ลำดับขั้นการสร้างเครื่องแบบคลิกเดียว
└── UI/                            หน้าจอทั้งหมด (SwiftUI)
guest/                             LinMO Agent (Python), linmo-ports.py และสคริปต์ติดตั้งใน Linux
guest/linmo-wayland/               compositor Wayland ของ LinMO (Rust + Smithay)
guest/tests/                       ทดสอบ agent และ linmo-wayland กับแอพจริง
scripts/                           build แอพ และฝังไฟล์ของ guest เข้าแอพ
```

### ปัญหาที่พบบ่อย

- **"The process doesn't have the com.apple.security.virtualization entitlement"**
  → เปิดผ่าน `build/LinMO.app` ที่ได้จากสคริปต์ ไม่ใช่กด Run ใน Xcode
- **ติดตั้งคลิกเดียวแล้วค้างนาน** → ปกติครั้งแรกใช้ 10–30 นาที ขึ้นกับความเร็วเน็ต ดูขั้นตอนล่าสุดที่แถบด้านล่าง
  ถ้าตัวเลขไม่ขยับเกิน 20 นาที ลองเช็กอินเทอร์เน็ตแล้วปิด-เปิดเครื่องใหม่
- **แถบแจ้งว่ามีขั้นตอนไม่สำเร็จ** → ใน Linux เปิด Terminal แล้วดู `sudo less /var/log/cloud-init-output.log`
- **บูตจาก ISO ไม่ขึ้น / จอดำ** → ตรวจว่า ISO เป็นรุ่น ARM64 ไม่ใช่ x86_64 (amd64)
- **บูตเข้าตัวติดตั้งซ้ำทุกครั้ง** → ปิดเครื่อง แล้วกด "ถอดแผ่นติดตั้ง"
- **เขียนไฟล์ใน ~/Mac ไม่ได้** → เครื่องที่ติดตั้งจาก ISO อาจมี uid ไม่ตรงกับ Mac ใช้ `sudo` หรือตั้ง uid ให้ตรงกับ `id -u` บน Mac
- **ค้างที่หน้าจอข้อความหลังตั้งค่าครั้งแรกเสร็จ** → กด **ปิดเครื่อง** แอพจะเปิดเครื่องใหม่เข้าหน้าจอ desktop ให้เอง
- **Linux ต่ออินเทอร์เน็ตไม่ได้** → เครื่องที่สร้างก่อน v0.10 อาจต้องแก้ไฟล์ netplan ครั้งเดียว ให้จับการ์ดแลนด้วย driver `virtio_net` แทน MAC address
- **"เครื่องนี้กำลังถูกใช้อยู่ในแอพ LinMO อีกตัวหนึ่ง"** → มีแอพ LinMO สองตัว (เช่นตัวใน `build/` กับตัวใน Applications) เปิดเครื่องเดียวกันอยู่
  ปิดเครื่องหรือปิดแอพตัวนั้นก่อน LinMO ล็อกไว้เพราะถ้าเปิดดิสก์เดียวกันซ้อนกัน ดิสก์ Linux จะเสีย
- **"เป็นต้นฉบับหรือสำเนาของเครื่องนี้และเปิดอยู่"** → ปิดเครื่องต้นฉบับหรือสำเนาก่อน เพราะใช้การ์ดเครือข่ายเดียวกัน
- **ไม่มีปุ่ม พอร์ต / SSH ใช้ไม่ได้** → อัปเดต LinMO Tools (ดูหัวข้อ LinMO Agent) แล้วรีสตาร์ตเครื่อง
- **ปุ่ม Snapshot กดไม่ได้** → เครื่องพักอยู่ กด **เปิดต่อ** แล้วปิดเครื่องก่อน

## License

MIT. See [LICENSE](LICENSE).
