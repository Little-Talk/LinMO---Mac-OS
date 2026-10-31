import Foundation

enum Preset: String, CaseIterable, Identifiable, Codable {
    case basic
    case learner
    case developer
    case securityLab
    case dataScience
    case design

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basic: return "พื้นฐาน"
        case .learner: return "สายเรียน Linux"
        case .developer: return "สาย dev"
        case .securityLab: return "สาย security lab"
        case .dataScience: return "สาย data science"
        case .design: return "สายออกแบบ"
        }
    }

    var summary: String {
        switch self {
        case .basic:
            return "หน้าจอ desktop และ Firefox — เบาที่สุด"
        case .learner:
            return "คู่มือคำสั่ง (man), vim/nano, htop, tree, git และไฟล์แนะนำคำสั่งแรกที่ควรลอง"
        case .developer:
            return "VS Code, git, build-essential, Python, Node.js, Go, Java, Docker และเครื่องมือ CLI ที่ใช้บ่อย"
        case .securityLab:
            return "nmap, Wireshark, tcpdump, John, hashcat, hydra, sqlmap และเครื่องมือฝึก CTF — ใช้กับระบบที่ได้รับอนุญาตเท่านั้น"
        case .dataScience:
            return "Python + JupyterLab, pandas, NumPy, SciPy, scikit-learn, matplotlib, seaborn, R + tidyverse และ SQLite"
        case .design:
            return "GIMP, Inkscape, Krita, Blender, darktable, Scribus, FontForge, ImageMagick และฟอนต์ไทย/Noto"
        }
    }

    var systemImage: String {
        switch self {
        case .basic: return "desktopcomputer"
        case .learner: return "graduationcap"
        case .developer: return "chevron.left.forwardslash.chevron.right"
        case .securityLab: return "lock.shield"
        case .dataScience: return "chart.bar.xaxis"
        case .design: return "paintbrush.pointed"
        }
    }

    var recommended: (cpu: Int, memoryGB: Int, diskGB: Int) {
        switch self {
        case .basic, .learner: return (2, 4, 32)
        case .developer, .dataScience, .design: return (4, 8, 64)
        case .securityLab: return (2, 4, 48)
        }
    }


    func packages(for family: Distro.Family) -> [String] {
        let apt = family != .fedora
        switch self {
        case .basic:
            return []
        case .learner:
            return apt
                ? ["man-db", "manpages", "bash-completion", "nano", "vim", "htop", "tree", "git", "curl", "wget",
                   "ncdu", "less", "fastfetch", "cowsay", "figlet", "sl", "python3"]
                : ["man-db", "man-pages", "bash-completion", "nano", "vim-enhanced", "htop", "tree", "git", "curl", "wget",
                   "ncdu", "less", "fastfetch", "cowsay", "figlet", "sl", "python3"]
        case .developer:
            return apt
                ? ["build-essential", "git", "curl", "wget", "jq", "make", "cmake", "gdb", "pkg-config",
                   "python3-pip", "python3-venv", "python3-dev", "nodejs", "npm", "golang", "default-jdk",
                   "docker.io", "docker-compose", "sqlite3", "ripgrep", "fd-find", "tmux", "htop", "tree", "meld"]
                : ["@development-tools", "gcc", "gcc-c++", "git", "curl", "wget", "jq", "make", "cmake", "gdb", "pkgconf",
                   "python3-pip", "python3-devel", "nodejs", "npm", "golang", "java-latest-openjdk-devel",
                   "moby-engine", "docker-compose", "sqlite", "ripgrep", "fd-find", "tmux", "htop", "tree", "meld"]
        case .securityLab:
            return apt
                ? ["nmap", "wireshark", "tcpdump", "netcat-openbsd", "socat", "john", "hashcat", "hydra", "sqlmap",
                   "gobuster", "dirb", "whois", "dnsutils", "traceroute", "binwalk", "foremost", "steghide",
                   "libimage-exiftool-perl", "python3-scapy", "python3-pwntools", "gdb", "aircrack-ng", "hashid",
                   "git", "curl", "wget", "vim", "tmux"]
                : ["nmap", "wireshark", "tcpdump", "nmap-ncat", "socat", "john", "hashcat", "hydra", "sqlmap",
                   "whois", "bind-utils", "traceroute", "binwalk", "foremost", "steghide",
                   "perl-Image-ExifTool", "python3-scapy", "gdb", "aircrack-ng",
                   "git", "curl", "wget", "vim-enhanced", "tmux"]
        case .dataScience:
            return apt
                ? ["python3-pip", "python3-venv", "python3-dev", "build-essential", "gfortran",
                   "python3-numpy", "python3-pandas", "python3-scipy", "python3-matplotlib", "python3-seaborn",
                   "python3-sklearn", "python3-statsmodels", "python3-sympy", "python3-openpyxl", "python3-ipykernel",
                   "ipython3", "jupyter-notebook", "r-base", "r-base-dev", "r-cran-tidyverse", "r-cran-irkernel",
                   "sqlite3", "csvkit", "git", "curl", "wget", "htop"]
                : ["python3-pip", "python3-devel", "gcc", "gcc-c++", "gcc-gfortran",
                   "python3-numpy", "python3-pandas", "python3-scipy", "python3-matplotlib", "python3-seaborn",
                   "python3-scikit-learn", "python3-statsmodels", "python3-sympy", "python3-openpyxl", "python3-ipykernel",
                   "python3-ipython", "python3-notebook", "R", "R-devel", "R-tidyverse", "R-IRkernel",
                   "sqlite", "python3-csvkit", "git", "curl", "wget", "htop"]
        case .design:
            return apt
                ? ["gimp", "inkscape", "krita", "blender", "darktable", "rawtherapee", "scribus", "fontforge",
                   "mypaint", "pinta", "gpick", "imagemagick", "librsvg2-bin", "webp", "optipng",
                   "fonts-noto-core", "fonts-noto-cjk", "fonts-noto-color-emoji", "fonts-thai-tlwg", "fonts-liberation2",
                   "fontconfig"]
                : ["gimp", "inkscape", "krita", "blender", "darktable", "rawtherapee", "scribus", "fontforge",
                   "mypaint", "pinta", "gpick", "ImageMagick", "librsvg2-tools", "libwebp-tools", "optipng",
                   "google-noto-sans-fonts", "google-noto-serif-fonts", "google-noto-sans-cjk-fonts",
                   "google-noto-color-emoji-fonts", "google-noto-sans-thai-fonts", "thai-scalable-waree-fonts",
                   "liberation-fonts", "fontconfig"]
        }
    }

    func commands(for family: Distro.Family, username: String) -> [String] {
        let packages = packages(for: family)
        guard !packages.isEmpty else { return [] }
        var commands: [String] = []
        let list = packages.joined(separator: " ")

        if family == .fedora {
            commands.append("dnf install -y --skip-unavailable \(list) || dnf install -y --setopt=strict=0 \(list) || true")
        } else {
            if self == .securityLab {
                commands.append("echo 'wireshark-common wireshark-common/install-setuid boolean true' | debconf-set-selections")
            }
            commands.append(
                "sh -c 'export DEBIAN_FRONTEND=noninteractive; apt-get install -y \(list) || for p in \(list); do apt-get install -y \"$p\" || true; done'"
            )
        }

        switch self {
        case .developer:
            commands.append(contentsOf: vsCodeCommands(for: family))
            commands.append("usermod -aG docker \(username) || true")
            commands.append("systemctl enable --now docker || true")
            if family != .fedora {
                commands.append("[ -e /usr/local/bin/fd ] || ln -s /usr/bin/fdfind /usr/local/bin/fd || true")
            }
        case .securityLab:
            commands.append("usermod -aG wireshark \(username) || true")
        case .dataScience:
            commands.append(contentsOf: jupyterLabCommands)
        case .design:
            commands.append("fc-cache -f || true")
        case .basic, .learner:
            break
        }
        return commands
    }

    private func vsCodeCommands(for family: Distro.Family) -> [String] {
        if family == .fedora {
            return [
                "rpm --import https://packages.microsoft.com/keys/microsoft.asc || true",
                "printf '[code]\\nname=Visual Studio Code\\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\\nenabled=1\\ngpgcheck=1\\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc\\n' > /etc/yum.repos.d/vscode.repo",
                "dnf install -y code || true",
            ]
        }
        return [
            "sh -c 'mkdir -p /etc/apt/keyrings && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /etc/apt/keyrings/packages.microsoft.gpg && echo \"deb [arch=arm64 signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main\" > /etc/apt/sources.list.d/vscode.list && apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y code' || true",
        ]
    }

    private var jupyterLabCommands: [String] {
        [
            "sh -c 'python3 -m venv --system-site-packages /opt/jupyterlab && /opt/jupyterlab/bin/pip install --no-cache-dir jupyterlab && ln -sf /opt/jupyterlab/bin/jupyter-lab /usr/local/bin/jupyter-lab' || true",
            "[ -x /opt/jupyterlab/bin/jupyter-lab ] && printf '[Desktop Entry]\\nType=Application\\nName=JupyterLab\\nComment=Notebook สำหรับ Python และ R\\nExec=jupyter-lab\\nTerminal=true\\nIcon=applications-science\\nCategories=Development;Science;Education;\\n' > /usr/share/applications/linmo-jupyterlab.desktop || true",
        ]
    }

    var welcomeFile: (name: String, content: String)? {
        switch self {
        case .basic:
            return nil
        case .learner:
            return ("เริ่มเรียน-Linux.txt", """
            ยินดีต้อนรับสู่ Linux! 🐧
            ==========================

            เปิด Terminal แล้วลองพิมพ์คำสั่งเหล่านี้ทีละบรรทัด (กด Enter หลังพิมพ์):

              pwd                 ตอนนี้อยู่โฟลเดอร์ไหน
              ls -la              ดูไฟล์ทั้งหมด รวมไฟล์ที่ซ่อนอยู่
              cd ~/Mac            ไปที่โฟลเดอร์ที่แชร์จาก Mac (ถ้าแชร์ไว้)
              tree -L 2           ดูโครงสร้างโฟลเดอร์
              cat /etc/os-release ดูว่าใช้ Linux รุ่นไหน
              fastfetch           ข้อมูลเครื่องแบบสวยๆ
              htop                ดูโปรแกรมที่ทำงานอยู่ (กด q เพื่อออก)
              man ls              อ่านคู่มือของคำสั่ง ls (กด q เพื่อออก)
              cowsay สวัสดี        ลองเล่น :)

            ติดตั้งโปรแกรมเพิ่ม:
              sudo apt install <ชื่อโปรแกรม>     (Debian / Ubuntu)
              sudo dnf install <ชื่อโปรแกรม>     (Fedora)

            ลองทำพังได้เลย! ก่อนลองอะไรเสี่ยงๆ ให้กด "Snapshot" ในแอพ LinMO (ตอนปิดเครื่อง)
            ถ้าพังก็ย้อนกลับได้ในคลิกเดียว

            """)
        case .developer:
            return ("เริ่มต้นสาย-dev.txt", """
            เครื่องสาย dev ของ LinMO
            ========================

            ติดตั้งไว้ให้แล้ว: VS Code (คำสั่ง code), git, gcc/make/cmake, Python 3 + pip/venv,
            Node.js + npm, Go, Java (JDK), Docker, sqlite3, jq, ripgrep (rg), fd, tmux

            เคล็ดลับ:
              - เปิด VS Code จากโหมด "หน้าต่างแยก" ของ LinMO จะได้หน้าต่างแยกบน Mac เหมือนแอพปกติ
              - เก็บโปรเจกต์ไว้ใน ~/Mac เพื่อแก้ไฟล์ได้ทั้งจาก Mac และ Linux
                (หรือเก็บใน ~/ ของ Linux ถ้าต้องการความเร็วในการ build สูงสุด)
              - Docker ใช้ได้โดยไม่ต้อง sudo หลังออกจากระบบแล้วเข้าใหม่หนึ่งครั้ง: docker run hello-world
              - สร้าง Python venv: python3 -m venv .venv && . .venv/bin/activate

            """)
        case .securityLab:
            return ("เริ่มต้น-security-lab.txt", """
            Security Lab ของ LinMO
            ======================

            ⚠️ ใช้เครื่องมือเหล่านี้กับระบบของตัวเอง หรือระบบที่ได้รับอนุญาตเป็นลายลักษณ์อักษรเท่านั้น
               การสแกนหรือโจมตีระบบของผู้อื่นโดยไม่ได้รับอนุญาตผิดกฎหมาย (พ.ร.บ. คอมพิวเตอร์ฯ)

            ติดตั้งไว้ให้แล้ว: nmap, Wireshark, tcpdump, netcat, socat, John the Ripper, hashcat, hydra,
            sqlmap, gobuster, dirb, binwalk, foremost, steghide, exiftool, scapy, pwntools, gdb

            ที่ฝึกที่ถูกกฎหมาย:
              - picoCTF, OverTheWire (เริ่มที่ Bandit), Hack The Box, TryHackMe
              - เปิดเครื่องเป้าหมายฝึกหัด (เช่น Metasploitable หรือ DVWA ใน Docker) ภายในเครื่องนี้เอง

            เคล็ดลับ:
              - กด "Snapshot" ในแอพ LinMO ก่อนทดลอง แล้วย้อนกลับเมื่อเสร็จ ได้เครื่องสะอาดทุกครั้ง
              - Wireshark ดักแพ็กเก็ตได้โดยไม่ต้อง sudo หลังออกจากระบบแล้วเข้าใหม่หนึ่งครั้ง
              - เครื่องนี้อยู่หลัง NAT ของ Mac: เครื่องอื่นในเครือข่ายมองไม่เห็นเครื่องนี้

            """)
        case .dataScience:
            return ("เริ่มต้นสาย-data-science.txt", """
            เครื่องสาย data science ของ LinMO
            =================================

            ติดตั้งไว้ให้แล้ว: Python 3 + pandas, NumPy, SciPy, scikit-learn, statsmodels, matplotlib, seaborn,
            SymPy, openpyxl, IPython, JupyterLab, R + tidyverse (และ kernel R ใน Jupyter), SQLite, csvkit

            เริ่มใช้:
              jupyter-lab         เปิด JupyterLab (หรือเลือก "JupyterLab" จากเมนูแอพ) แล้วเปิดใน Firefox
              ipython3            Python แบบโต้ตอบ
              R                   เปิด R (ลอง library(tidyverse))
              csvlook data.csv    ดูไฟล์ CSV เป็นตารางใน Terminal

            เคล็ดลับ:
              - เก็บข้อมูลและ notebook ไว้ใน ~/Mac เพื่อเปิดได้ทั้งจาก Mac และ Linux
              - ไลบรารีเพิ่มเติม: สร้าง venv ของโปรเจกต์ก่อน แล้วค่อย pip install
                  python3 -m venv --system-site-packages .venv && . .venv/bin/activate && pip install polars
              - เครื่องนี้ไม่มี GPU (ข้อจำกัดของ Mac) — PyTorch / TensorFlow ใช้ CPU ได้ แต่ฝึกโมเดลใหญ่จะช้า
              - ถ้าข้อมูลใหญ่ เพิ่ม RAM ได้ในหน้าตั้งค่าเครื่องของ LinMO (ตอนปิดเครื่อง)

            """)
        case .design:
            return ("เริ่มต้นสายออกแบบ.txt", """
            เครื่องสายออกแบบของ LinMO
            =========================

            ติดตั้งไว้ให้แล้ว: GIMP (แต่งรูป), Inkscape (vector), Krita และ MyPaint (วาดรูป), Pinta,
            Blender (3D), darktable และ RawTherapee (ไฟล์ RAW), Scribus (จัดหน้าสิ่งพิมพ์),
            FontForge (ทำฟอนต์), gpick (ดูดสี), ImageMagick, rsvg-convert, cwebp, optipng
            และฟอนต์ Noto (รวมจีน/ญี่ปุ่น/เกาหลี และอีโมจิ) + ฟอนต์ไทย

            เคล็ดลับ:
              - เปิดแอพจากโหมด "หน้าต่างแยก" ของ LinMO หรือค้นหาใน Spotlight ได้เหมือนแอพ Mac
              - copy-paste รูปภาพระหว่าง Mac กับแอพใน Linux ได้ทั้งสองทาง
              - เก็บงานไว้ใน ~/Mac เพื่อเปิดต่อในแอพบน Mac ได้ทันที
              - เครื่องนี้ไม่มี GPU (ข้อจำกัดของ Mac) — Blender ใช้การวาดด้วย CPU: viewport ช้ากว่าปกติ
                ให้ render ด้วย Cycles (CPU) หรือ Eevee ในฉากเล็กๆ
              - เมาส์ปากกา/แท็บเล็ตใช้ได้แบบเมาส์ แต่อาจไม่มีแรงกด
              - ติดตั้งฟอนต์เพิ่ม: คัดลอกไฟล์ฟอนต์ไปไว้ใน ~/.local/share/fonts แล้วรัน fc-cache -f

            """)
        }
    }
}
