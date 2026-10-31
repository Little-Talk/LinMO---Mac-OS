#!/usr/bin/env python3
import base64
import hashlib
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
FILES = {
    "agent": "guest/linmo-agent.py",
    "install": "guest/install.sh",
    "installWine": "guest/install-wine.sh",
}
OUT = ROOT / "Sources/LinMO/Guest/GuestFiles.generated.swift"
WAYLAND = ROOT / "guest/linmo-wayland"
BINARY = ROOT / "guest/bin/linmo-wayland-aarch64"

digest = hashlib.sha256()
lines = [
    "import Foundation",
    "",
    "enum GuestFiles {",
]
for name, rel in FILES.items():
    data = (ROOT / rel).read_bytes()
    digest.update(data)
    encoded = base64.b64encode(data).decode()
    lines.append(f'    static let {name}Base64 = "{encoded}"')
    lines.append(f"    static var {name}: Data {{ Data(base64Encoded: {name}Base64)! }}")
    lines.append("")
sources = [WAYLAND / "Cargo.toml", WAYLAND / "Cargo.lock"] + sorted((WAYLAND / "src").glob("*.rs"))
lines.append("    static let waylandSource: [(String, String)] = [")
for path in sources:
    data = path.read_bytes()
    digest.update(data)
    rel = path.relative_to(WAYLAND).as_posix()
    lines.append(f'        ("{rel}", "{base64.b64encode(data).decode()}"),')
lines.append("    ]")
lines.append("")
if BINARY.exists():
    digest.update(BINARY.read_bytes())

lines.append(f'    static let version = "{digest.hexdigest()[:12]}"')
lines.append("}")
lines.append("")

OUT.parent.mkdir(parents=True, exist_ok=True)
content = "\n".join(lines)
if not OUT.exists() or OUT.read_text() != content:
    OUT.write_text(content)
    print(f"updated {OUT.relative_to(ROOT)}")
