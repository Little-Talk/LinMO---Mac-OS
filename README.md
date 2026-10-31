# LinMO — Linux on macOS

ใช้ Linux บน Mac แบบง่ายที่สุด และเปิดแอพ Linux เป็นหน้าต่างแยกบน Mac เหมือนแอพปกติ

> สถานะ: **v0.9 (เวอร์ชันทดลอง)** — แอพ Linux อยู่ใน Launchpad, Spotlight และเมนู "แอพ Linux" บนแถบเมนู,
> ชุดสำเร็จรูป (สายเรียน Linux / สาย dev / สาย security lab / สาย data science / สายออกแบบ), copy-paste รูปภาพ และเตรียมพร้อมส่งขึ้น Mac App Store
> แผนพัฒนาต่อดู [docs/ROADMAP.md](docs/ROADMAP.md)

## ฟีเจอร์

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
- **แชร์โฟลเดอร์** — โฟลเดอร์จาก Mac โผล่ที่ `~/Mac` ใน Linux อัตโนมัติ
- **แชร์ clipboard** — copy บน Mac แล้ว paste ใน Linux ได้ (และกลับกัน)
- **Snapshot** — บันทึกสถานะเครื่อง ทำพังแล้วย้อนกลับได้ในไม่กี่วินาที
- **Rosetta** — รันโปรแกรม Linux แบบ x86_64 ได้
- **หลายเครื่อง** — สร้างได้หลายเครื่องในแอพเดียว
- **ติดตั้งเองจาก ISO** — ใช้ distro อื่นที่เป็น ARM64 ได้ เช่น Ubuntu, Fedora

## สิ่งที่ต้องมี

- Mac ชิป Apple (M1 ขึ้นไป)
- macOS 14 Sonoma ขึ้นไป
- Xcode 15 ขึ้นไป (หรือ Command Line Tools ที่มี Swift 5.9+)
- อินเทอร์เน็ต (สำหรับติดตั้งแบบคลิกเดียว)

## วิธี build และเปิดแอพ

```bash
git clone https://github.com/jeerapatsepu/LinMO.git
cd LinMO
./scripts/build-app.sh release --run
```

แอพจะอยู่ที่ `build/LinMO.app` ลากไปไว้ใน Applications ได้เลย

> **สำคัญ:** การกด Run ใน Xcode ตรงๆ จะเปิดเครื่องไม่ได้ เพราะแอพต้องมีสิทธิ์
> `com.apple.security.virtualization` ให้ใช้สคริปต์ด้านบน ซึ่งเซ็นสิทธิ์ให้อัตโนมัติ

ทดสอบรุ่น App Store (เปิด App Sandbox) บนเครื่องตัวเอง: `./scripts/build-app.sh sandbox --run`
ขั้นตอนส่งขึ้น Mac App Store ดู [docs/APP_STORE.md](docs/APP_STORE.md)

## วิธีใช้งาน

### แบบคลิกเดียว (แนะนำ)

1. กด **+** → เลือก **Debian**, **Ubuntu** หรือ **Fedora** → ถัดไป
2. เลือกชุดโปรแกรม (พื้นฐาน / สายเรียน Linux / สาย dev / สาย security lab / สาย data science / สายออกแบบ) หน้าจอ (XFCE / GNOME)
   ตั้งชื่อผู้ใช้ รหัสผ่าน และตัวเลือกภาษาไทย → **ติดตั้ง**
3. รอดาวน์โหลด (ครั้งแรกประมาณ 450–600 MB ครั้งต่อไปใช้ไฟล์เดิมได้ทันที)
4. กด **เปิดเครื่อง** — ครั้งแรก Linux จะติดตั้งหน้าจอและภาษาไทยเอง ใช้เวลาประมาณ 10–30 นาที
   ดูความคืบหน้าได้ที่แถบด้านล่างของหน้าจอ เมื่อเสร็จแอพจะเปิดเครื่องใหม่เข้าหน้าจอ desktop ให้เอง

> Fedora มีให้เฉพาะ XFCE เพราะ GNOME ของ Fedora รุ่นใหม่ใช้ Wayland อย่างเดียว ซึ่งยังแชร์ clipboard กับ Mac ไม่ได้

### โหมดหน้าต่างแยก

1. เปิดเครื่อง แล้วกดปุ่ม **หน้าต่างแยก** ที่แถบด้านบน
2. หน้าจอ Linux จะถูกแทนด้วยรายการแอพ — คลิกแอพที่ต้องการ แอพจะเปิดเป็นหน้าต่าง Mac
3. หน้าต่างที่เปิดอยู่แล้วใน Linux จะโผล่มาเป็นหน้าต่าง Mac ด้วย
4. กดปุ่ม **หน้าต่างแยก** อีกครั้งเพื่อกลับไปดูหน้าจอ Linux ทั้งจอ

คีย์บอร์ดในโหมดนี้: **Cmd** ทำหน้าที่เป็น **Ctrl** (Cmd+C, Cmd+V, Cmd+S ใช้ได้เหมือนบน Mac),
Control+คลิก = คลิกขวา, Cmd+Q ยังเป็นการปิดแอพ LinMO
ตัวอักษรพิมพ์ผ่านระบบพิมพ์ของ Mac จึงสลับไทย/อังกฤษด้วยปุ่มของ Mac ได้เลย
(ปิดได้ที่ ตั้งค่าเครื่อง → "พิมพ์ด้วยแป้นพิมพ์ของ Mac" ถ้าต้องการให้ Option เป็น Alt)

### แอพ Linux ใน Spotlight, Launchpad และแถบเมนู

ทุกครั้งที่เปิดเครื่อง LinMO จะจำรายการแอพของเครื่องนั้นไว้ แล้วให้เปิดแอพได้จากทุกที่บน Mac:

- **Spotlight** — กด Cmd+Space พิมพ์ชื่อแอพ Linux (เช่น "Firefox", "Terminal")
- **เมนู "แอพ Linux"** — ไอคอนตารางบนแถบเมนู แยกตามเครื่องและหมวดหมู่
- **Launchpad** — เปิดที่ LinMO → Settings… → "ใส่แอพ Linux ใน Launchpad" (ทางลัดอยู่ที่ `~/Applications/แอพ Linux (LinMO)`)

ถ้าเครื่องยังปิดอยู่ LinMO จะเปิดเครื่องให้ แล้วเปิดแอพเป็นหน้าต่างแยกเมื่อ Linux พร้อม
ปิด/เปิดแต่ละอย่างได้ที่ LinMO → Settings…

ถ้าแอพขึ้นปุ่มอัปเดต agent (ลูกศรสีส้ม) ให้คลิกแล้วคัดลอกคำสั่งไปวางใน Terminal ของ Linux

เครื่องที่สร้างด้วยตัวช่วยติดตั้งตั้งแต่ v0.4 มี LinMO Agent ให้แล้ว
เครื่องที่สร้างก่อนหน้านั้นหรือติดตั้งจาก ISO: กดปุ่ม **หน้าต่างแยก** แล้วคัดลอกคำสั่งติดตั้งไปวางใน Terminal ของ Linux
(แอพต่อแผ่น LinMO Tools ให้ทุกเครื่องอยู่แล้ว) จากนั้นออกจากระบบแล้วเข้าใหม่

> ต้องใช้หน้าจอแบบ X11 (XFCE หรือ GNOME on Xorg ที่ LinMO ตั้งให้) — ยังไม่รองรับเซสชัน Wayland

### แอพ Wayland (ทดลอง)

LinMO มี compositor Wayland ของตัวเอง (**linmo-wayland**) ที่ทำงานเบื้องหลังใน Linux
แอพที่เปิดผ่านมันจะเป็นหน้าต่าง Mac ได้เลย ไม่ว่า Linux จะใช้ X11 หรือ Wayland

- เปิดใช้: ปิดเครื่อง → ตั้งค่าเครื่อง → **เปิดแอพผ่าน Wayland (ทดลอง)**
- ถ้า Linux ใช้ Wayland อย่างเดียว (เช่น Fedora GNOME, Ubuntu 25.10+) LinMO จะใช้ linmo-wayland ให้อัตโนมัติ
- รองรับ copy-paste (ข้อความ + รูปภาพ), ลากไฟล์เข้า/ออก, ไอคอนหน้าต่าง, เมนู, พิมพ์ไทย/ญี่ปุ่น และแอพ X11 ผ่าน Xwayland
- ข้อจำกัดของแอพ X11 ในโหมดนี้: copy รูปจากแอพ X11 ไป Mac ไม่ได้ และ paste จาก Mac ได้ไม่เกิน 64 KB ต่อครั้ง
  (ข้อจำกัดของ Smithay 0.7 — แอพ X11 ในโหมด X11 agent ปกติไม่มีข้อจำกัดนี้)

ไฟล์ของ linmo-wayland สำหรับ Linux ARM64 สร้างโดย GitHub Actions (`.github/workflows/linmo-wayland.yml`)
แล้ว commit ไว้ที่ `guest/bin/` — ถ้ายังไม่มี เครื่อง Linux จะสร้างจากซอร์สโค้ดเองตอนติดตั้ง (ต้องมี Rust 1.80+)

ทดสอบบนเครื่อง Linux ใดก็ได้: `python3 guest/tests/wayland_smoke.py guest/linmo-wayland/target/release/linmo-wayland`

### ติดตั้งเองจาก ISO

1. กด **+** → **ติดตั้งเองจากไฟล์ ISO** → เลือกไฟล์ ISO รุ่น **ARM64 / aarch64**
2. เปิดเครื่อง แล้วติดตั้งตามขั้นตอนของ distro
3. ติดตั้งเสร็จ ปิดเครื่อง กด **ถอดแผ่นติดตั้ง** แล้วเปิดใหม่

เครื่องแบบนี้ต้องตั้งค่าบางอย่างใน Linux เอง:

```bash
# clipboard
sudo apt install spice-vdagent        # หรือ: sudo dnf install spice-vdagent

# โฟลเดอร์แชร์ (ตั้งโฟลเดอร์ในแอพก่อน)
sudo mkdir -p /mnt/linmo
echo 'linmo /mnt/linmo virtiofs rw,nofail 0 0' | sudo tee -a /etc/fstab
sudo mount -a
```

### Rosetta (สำหรับเครื่องที่ติดตั้งจาก ISO หรือเปิดใช้ทีหลัง)

เปิด Rosetta ในหน้า **ตั้งค่าเครื่อง** แล้วใน Linux สั่ง:

```bash
sudo mkdir -p /media/rosetta
echo 'rosetta /media/rosetta virtiofs ro,nofail 0 0' | sudo tee -a /etc/fstab
sudo mount -a
sudo /usr/sbin/update-binfmts --install rosetta /media/rosetta/rosetta \
  --magic "\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00" \
  --mask "\xff\xff\xff\xff\xff\xfe\xfe\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff" \
  --credentials yes --preserve no --fix-binary yes
```

(ต้องมีแพ็กเกจ `binfmt-support` บน Debian/Ubuntu)

## ไฟล์เก็บไว้ที่ไหน

| ที่อยู่ | คืออะไร |
|---|---|
| `~/Library/Application Support/LinMO/Machines/<id>.vmbundle/` | เครื่องแต่ละเครื่อง (ดิสก์, NVRAM, config, snapshot) |
| `~/Library/Caches/LinMO/` | ไฟล์ Linux ที่ดาวน์โหลดไว้ ดูขนาดและลบได้ที่ **LinMO → Settings…** |
| `~/Library/Application Support/LinMO/LinuxApps.json` | รายการแอพ Linux ที่จำไว้ (สำหรับ Spotlight, เมนู และ Launchpad) |
| `~/Applications/แอพ Linux (LinMO)/` | ทางลัดของแอพ Linux ใน Launchpad (ถ้าเปิดใช้) |

รุ่น Mac App Store (App Sandbox) เก็บทุกอย่างใน `~/Library/Containers/io.github.jeerapatsepu.LinMO/` แทน

เครื่องจาก v0.1 จะถูกย้ายมาที่ใหม่ให้อัตโนมัติ

## โครงสร้างโค้ด

```
Sources/LinMO/
├── LinMOApp.swift
├── Model/
│   ├── MachineConfig.swift        การตั้งค่าเครื่อง, Snapshot
│   ├── MachineBundle.swift        ไฟล์ของเครื่อง, สร้าง/ลบ, snapshot ด้วย APFS clone
│   └── SecurityScopedBookmark.swift  สิทธิ์ไฟล์/โฟลเดอร์ที่ผู้ใช้เลือก (App Sandbox)
├── Launcher/
│   ├── LinuxAppCatalog.swift      รายการแอพ Linux ทุกเครื่อง + Spotlight
│   └── LaunchpadShortcuts.swift   ทางลัดใน Launchpad + เปิดแอพจาก linmo://launch
├── VM/
│   ├── ConfigurationBuilder.swift สร้าง config ของ Virtualization.framework, Rosetta
│   ├── MachineController.swift    เปิด/ปิดเครื่อง, ตั้งค่า, snapshot
│   ├── SetupProgressListener.swift รับความคืบหน้าจาก Linux ผ่าน vsock
│   └── MachineLibrary.swift       รายการเครื่อง, ย้ายข้อมูลจาก v0.1
├── Seamless/                      โหมดหน้าต่างแยก: การเชื่อมต่อ, หน้าต่าง Mac, แปลงปุ่มคีย์บอร์ด
├── Guest/                         ไฟล์ของ agent ที่ฝังในแอพ + สร้างแผ่น LinMO Tools
├── Provisioning/
│   ├── DistroCatalog.swift        รายการ distro และหน้าจอ desktop ที่ติดตั้งคลิกเดียวได้
│   ├── ImageStore.swift           หา URL, ดาวน์โหลด, ตรวจ checksum, แคช
│   ├── DiskConverters.swift       แปลง qcow2 / xz เป็นดิสก์ raw แบบ sparse
│   ├── CloudInit.swift            สูตรตั้งค่าแต่ละ distro + สคริปต์รายงานความคืบหน้า
│   ├── Presets.swift              ชุดสำเร็จรูป: สายเรียน Linux / dev / security lab / data science / ออกแบบ
│   └── Provisioner.swift          ลำดับขั้นการสร้างเครื่องแบบคลิกเดียว
└── UI/                            หน้าจอทั้งหมด (SwiftUI)
guest/                             LinMO Agent (Python) และสคริปต์ติดตั้งใน Linux
guest/linmo-wayland/               compositor Wayland ของ LinMO (Rust + Smithay)
guest/tests/                       ทดสอบ linmo-wayland กับแอพจริง
docs/PROTOCOL.md                   โปรโตคอลระหว่างแอพกับ agent
docs/APP_STORE.md                  ขั้นตอนส่งขึ้น Mac App Store
```

## ปัญหาที่พบบ่อย

- **"The process doesn't have the com.apple.security.virtualization entitlement"**
  → เปิดผ่าน `build/LinMO.app` ที่ได้จากสคริปต์ ไม่ใช่กด Run ใน Xcode
- **ติดตั้งคลิกเดียวแล้วค้างนาน** → ปกติครั้งแรกใช้ 10–30 นาที ขึ้นกับความเร็วเน็ต ดูขั้นตอนล่าสุดที่แถบด้านล่าง
  ถ้าตัวเลขไม่ขยับเกิน 20 นาที ลองเช็กอินเทอร์เน็ตแล้วปิด-เปิดเครื่องใหม่
- **แถบแจ้งว่ามีขั้นตอนไม่สำเร็จ** → ใน Linux เปิด Terminal แล้วดู `sudo less /var/log/cloud-init-output.log`
- **บูตจาก ISO ไม่ขึ้น / จอดำ** → ตรวจว่า ISO เป็นรุ่น ARM64 ไม่ใช่ x86_64 (amd64)
- **บูตเข้าตัวติดตั้งซ้ำทุกครั้ง** → ปิดเครื่อง แล้วกด "ถอดแผ่นติดตั้ง"
- **เขียนไฟล์ใน ~/Mac ไม่ได้** → เครื่องที่ติดตั้งจาก ISO อาจมี uid ไม่ตรงกับ Mac ใช้ `sudo` หรือตั้ง uid ให้ตรงกับ `id -u` บน Mac

## License

MIT — ดู [LICENSE](LICENSE)
