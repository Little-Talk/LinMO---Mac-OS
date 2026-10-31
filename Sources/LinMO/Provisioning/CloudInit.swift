import Foundation

struct GuestSetupOptions {
    var hostname: String
    var username: String
    var password: String
    var desktop: Desktop = .xfce
    var uid: Int = Int(getuid())
    var timezone: String = TimeZone.current.identifier
    var thaiKeyboard: Bool = true
    var thaiInterface: Bool = false
    var autologin: Bool = true
    var rosetta: Bool = false
    var preset: Preset = .basic

    static func isValidUsername(_ name: String) -> Bool {
        name.range(of: "^[a-z_][a-z0-9_-]{0,31}$", options: .regularExpression) != nil
            && !["root", "daemon", "bin", "sys", "nobody", "admin", "ubuntu", "debian", "fedora"].contains(name)
    }

    static func hostname(from name: String) -> String {
        var result = ""
        for scalar in name.lowercased().unicodeScalars {
            if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) {
                result.unicodeScalars.append(scalar)
            } else if !result.isEmpty && !result.hasSuffix("-") {
                result += "-"
            }
        }
        while result.hasSuffix("-") { result.removeLast() }
        return result.isEmpty ? "linmo" : String(result.prefix(63))
    }
}

enum SetupReporter {
    static let port: UInt32 = 5201
}

enum CloudInit {


    static func metaData(instanceID: UUID, hostname: String) -> String {
        """
        instance-id: \(instanceID.uuidString.lowercased())
        local-hostname: \(hostname)

        """
    }


    private enum DisplayManager {
        case lightdm
        case gdm(configPath: String)
    }

    private struct Recipe {
        var packages: [String]
        var adminGroup: String
        var displayManager: DisplayManager
        var localeCommands: [String]
        var extraFiles: [(path: String, content: String)] = []
        var extraCommands: [String] = []
    }

    private static func recipe(for family: Distro.Family, desktop: Desktop, locale: String) -> Recipe {
        switch family {
        case .debian:
            let desktopPackages: [String]
            switch desktop {
            case .xfce:
                desktopPackages = ["xorg", "xfce4", "xfce4-terminal", "lightdm", "lightdm-gtk-greeter", "dbus-x11"]
            case .gnome:
                desktopPackages = ["gnome-core", "gdm3", "dconf-cli"]
            }
            return Recipe(
                packages: desktopPackages + [
                    "firefox-esr", "locales", "fonts-thai-tlwg", "fonts-noto-core", "spice-vdagent",
                    "python3-xlib", "libgtk-3-bin",
                ],
                adminGroup: "sudo",
                displayManager: desktop == .gnome ? .gdm(configPath: "/etc/gdm3/daemon.conf") : .lightdm,
                localeCommands: ["locale-gen", "update-locale LANG=\(locale)"],
                extraFiles: [("/etc/locale.gen", "en_US.UTF-8 UTF-8\nth_TH.UTF-8 UTF-8\n")]
            )

        case .ubuntu:
            let desktopPackages: [String]
            var extraCommands: [String] = []
            switch desktop {
            case .xfce:
                desktopPackages = ["xorg", "xfce4", "xfce4-terminal", "lightdm", "lightdm-gtk-greeter", "dbus-x11"]
                extraCommands = ["snap install firefox || true"]
            case .gnome:
                desktopPackages = ["ubuntu-desktop-minimal", "dconf-cli"]
            }
            return Recipe(
                packages: desktopPackages + [
                    "locales", "language-pack-th", "fonts-thai-tlwg", "fonts-noto-core", "spice-vdagent",
                    "python3-xlib", "libgtk-3-bin",
                ],
                adminGroup: "sudo",
                displayManager: desktop == .gnome ? .gdm(configPath: "/etc/gdm3/custom.conf") : .lightdm,
                localeCommands: ["locale-gen en_US.UTF-8 th_TH.UTF-8", "update-locale LANG=\(locale)"],
                extraCommands: extraCommands
            )

        case .fedora:
            return Recipe(
                packages: [
                    "@xfce-desktop-environment", "firefox",
                    "glibc-langpack-en", "glibc-langpack-th", "google-noto-sans-thai-fonts", "spice-vdagent",
                    "python3-xlib",
                ],
                adminGroup: "wheel",
                displayManager: .lightdm,
                localeCommands: ["localectl set-locale LANG=\(locale) || true"]
            )
        }
    }


    static func userData(for distro: Distro, options o: GuestSetupOptions) -> String {
        let locale = o.thaiInterface ? "th_TH.UTF-8" : "en_US.UTF-8"
        let desktop = distro.desktops.contains(o.desktop) ? o.desktop : distro.desktops[0]
        let recipe = recipe(for: distro.family, desktop: desktop, locale: locale)
        let home = "/home/\(o.username)"

        var y = "#cloud-config\n"
        y += "hostname: \(q(o.hostname))\n"
        y += "timezone: \(q(o.timezone))\n"
        y += "ssh_pwauth: false\n\n"

        let reporter = Data(reporterScript.utf8).base64EncodedString()
        y += "bootcmd:\n"
        y += "  - [sh, -c, \(q("mkdir -p /usr/local/libexec && echo \(reporter) | base64 -d > /usr/local/libexec/linmo-setup-reporter && chmod 755 /usr/local/libexec/linmo-setup-reporter && (systemd-run --no-block --unit=linmo-setup-reporter --collect -p DefaultDependencies=no python3 /usr/local/libexec/linmo-setup-reporter || true)"))]\n\n"

        y += "users:\n"
        y += "  - name: \(q(o.username))\n"
        y += "    gecos: \(q(o.username))\n"
        y += "    uid: \(o.uid)\n"
        y += "    shell: /bin/bash\n"
        y += "    groups: [\(recipe.adminGroup), audio, video]\n"
        y += "    lock_passwd: false\n"
        y += "    plain_text_passwd: \(q(o.password))\n\n"

        y += "package_update: true\n"
        y += "packages:\n"
        for p in recipe.packages { y += "  - \(q(p))\n" }
        y += "\n"

        y += "write_files:\n"
        for f in recipe.extraFiles {
            y += file(path: f.path, content: f.content)
        }

        switch recipe.displayManager {
        case .lightdm:
            var conf = "[Seat:*]\nuser-session=xfce\n"
            if o.autologin {
                conf += "autologin-user=\(o.username)\nautologin-user-timeout=0\n"
            }
            y += file(path: "/etc/lightdm/lightdm.conf.d/50-linmo.conf", deferred: true, content: conf)

        case .gdm(let configPath):
            var conf = "[daemon]\nWaylandEnable=false\n"
            if o.autologin {
                conf += "AutomaticLoginEnable=true\nAutomaticLogin=\(o.username)\n"
            }
            y += file(path: configPath, deferred: true, content: conf)
            if o.thaiKeyboard {
                y += file(path: "/etc/dconf/db/local.d/00-linmo", deferred: true, content: """
                [org/gnome/desktop/input-sources]
                sources=[('xkb', 'us'), ('xkb', 'th')]

                """)
            }
        }

        y += binaryFile(path: "/usr/local/lib/linmo/linmo-agent.py", permissions: "0755", base64: GuestFiles.agentBase64)
        y += file(path: "/etc/xdg/autostart/linmo-agent.desktop", content: """
        [Desktop Entry]
        Type=Application
        Name=LinMO Agent
        Exec=python3 /usr/local/lib/linmo/linmo-agent.py
        NoDisplay=true
        X-GNOME-Autostart-enabled=true

        """)

        if let welcome = o.preset.welcomeFile {
            y += file(path: "\(home)/\(welcome.name)", deferred: true, content: welcome.content)
        }

        if o.rosetta {
            y += file(path: "/usr/local/sbin/linmo-rosetta", permissions: "0755", content: rosettaScript)
            y += file(path: "/etc/systemd/system/linmo-rosetta.service", content: """
            [Unit]
            Description=LinMO: register Rosetta for x86_64 programs
            After=media-rosetta.mount proc-sys-fs-binfmt_misc.mount
            Requires=media-rosetta.mount

            [Service]
            Type=oneshot
            ExecStart=/usr/local/sbin/linmo-rosetta
            RemainAfterExit=yes

            [Install]
            WantedBy=multi-user.target

            """)
        }
        y += "\n"

        var commands = recipe.localeCommands
        if o.thaiKeyboard {
            commands.append("localectl set-x11-keymap us,th pc105 , grp:alt_shift_toggle || true")
        }
        if case .gdm = recipe.displayManager, o.thaiKeyboard {
            commands.append("[ -e /etc/dconf/profile/user ] || printf 'user-db:user\\nsystem-db:local\\n' > /etc/dconf/profile/user")
            commands.append("dconf update || true")
        }
        commands += [
            "mkdir -p /mnt/linmo",
            "grep -q '^\(SharedTags.folder) ' /etc/fstab || echo '\(SharedTags.folder) /mnt/linmo virtiofs rw,nofail 0 0' >> /etc/fstab",
            "ln -sfn /mnt/linmo \(home)/Mac",
            "chown -h \(o.username):\(o.username) \(home)/Mac || true",
        ]
        if o.rosetta {
            commands += [
                "mkdir -p /media/rosetta",
                "grep -q '^\(SharedTags.rosetta) ' /etc/fstab || echo '\(SharedTags.rosetta) /media/rosetta virtiofs ro,nofail 0 0' >> /etc/fstab",
                "systemctl daemon-reload",
                "systemctl enable linmo-rosetta.service",
            ]
        }
        commands += recipe.extraCommands
        commands += o.preset.commands(for: distro.family, username: o.username)
        if let welcome = o.preset.welcomeFile {
            commands.append("chown \(o.username):\(o.username) '\(home)/\(welcome.name)' || true")
        }
        commands.append("sh -c 'mkdir -p /mnt/linmo-tools; for d in /dev/vd? /dev/sr?; do mount -o ro \"$d\" /mnt/linmo-tools 2>/dev/null || continue; [ -e /mnt/linmo-tools/install.sh ] && break; umount /mnt/linmo-tools; done; sh /mnt/linmo-tools/install.sh; umount /mnt/linmo-tools' || true")
        commands.append("systemctl set-default graphical.target")

        y += "runcmd:\n"
        for c in commands { y += "  - \(q(c))\n" }
        y += "\n"

        y += "power_state:\n"
        y += "  mode: reboot\n"
        y += "  message: \(q("LinMO: setup finished, rebooting"))\n"
        y += "  condition: true\n"
        return y
    }


    static let reporterScript = #"""
    #!/usr/bin/env python3
    import json, os, re, socket, subprocess, time

    DONE = "/var/lib/cloud/instance/boot-finished"
    RESULT = "/run/cloud-init/result.json"
    LOG = "/var/log/cloud-init-output.log"
    PORT = 5201

    if os.path.exists(DONE):
        raise SystemExit(0)

    apt_total = re.compile(r"(\d+) newly installed")
    apt_step = re.compile(r"^Setting up ")
    dnf_step = re.compile(r"\[\s*(\d+)/(\d+)\]")

    offset, total, done, last = 0, 0, 0, "Starting setup"
    sock, finished_at = None, None

    def connect():
        try:
            s = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
            s.settimeout(3)
            s.connect((2, PORT))
            return s
        except OSError:
            return None

    while True:
        try:
            with open(LOG, "r", errors="replace") as f:
                f.seek(offset)
                chunk = f.read()
                offset = f.tell()
        except OSError:
            chunk = ""
        for line in chunk.splitlines():
            line = line.strip()
            if not line:
                continue
            last = line[-160:]
            m = apt_total.search(line)
            if m:
                total += int(m.group(1))
            if apt_step.match(line):
                done += 1
            m = dnf_step.search(line)
            if m:
                done, total = int(m.group(1)), int(m.group(2))

        finished = os.path.exists(DONE)
        msg = {"state": "done" if finished else "running", "line": last}
        if total > 0:
            msg["progress"] = min(done / total, 1.0)
        if finished:
            try:
                with open(RESULT) as f:
                    msg["errors"] = len(json.load(f).get("v1", {}).get("errors", []))
            except (OSError, ValueError):
                pass
            finished_at = finished_at or time.time()

        if sock is None:
            sock = connect()
        if sock is not None:
            try:
                sock.sendall((json.dumps(msg) + "\n").encode())
                if finished:
                    break
            except OSError:
                sock.close()
                sock = None
        if finished and time.time() - finished_at > 30:
            break
        time.sleep(2)

    try:
        subprocess.run(["cloud-init", "status", "--wait"], timeout=900,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass
    time.sleep(20)
    subprocess.run(["systemctl", "reboot"])

    """#

    private static let rosettaScript = #"""
    #!/bin/sh
    set -e
    [ -x /media/rosetta/rosetta ] || exit 0
    [ -e /proc/sys/fs/binfmt_misc/rosetta ] && exit 0
    printf '%s\n' ':rosetta:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00:\xff\xff\xff\xff\xff\xfe\xfe\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/media/rosetta/rosetta:CF' > /proc/sys/fs/binfmt_misc/register

    """#


    private static func q(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }

    private static func file(path: String, permissions: String = "0644", deferred: Bool = false, content: String) -> String {
        var y = "  - path: \(q(path))\n"
        y += "    permissions: \(q(permissions))\n"
        if deferred { y += "    defer: true\n" }
        y += "    content: |\n"
        var lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        if content.hasSuffix("\n") { lines.removeLast() }
        for line in lines {
            y += line.isEmpty ? "\n" : "      \(line)\n"
        }
        return y
    }

    private static func binaryFile(path: String, permissions: String, base64: String) -> String {
        var y = "  - path: \(q(path))\n"
        y += "    permissions: \(q(permissions))\n"
        y += "    encoding: b64\n"
        y += "    content: \(base64)\n"
        return y
    }


    static func makeSeedImage(at destination: URL, userData: String, metaData: String) throws {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("linmo-seed-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        try userData.write(to: staging.appendingPathComponent("user-data"), atomically: true, encoding: .utf8)
        try metaData.write(to: staging.appendingPathComponent("meta-data"), atomically: true, encoding: .utf8)

        try? fm.removeItem(at: destination)
        try Shell.run("/usr/bin/hdiutil", [
            "makehybrid", "-iso", "-joliet",
            "-default-volume-name", "cidata",
            "-o", destination.path,
            staging.path,
        ])
        guard fm.fileExists(atPath: destination.path) else {
            throw LinMOError.message("สร้างแผ่น cloud-init ไม่สำเร็จ")
        }
    }
}

enum Shell {
    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let name = URL(fileURLWithPath: executable).lastPathComponent
            throw LinMOError.message("\(name) ทำงานไม่สำเร็จ: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return text
    }
}
