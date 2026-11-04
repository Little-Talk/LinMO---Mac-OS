#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

PUBLISH="${1:-}"
REPO="${GITHUB_REPO:-Little-Talk/LinMO---Mac-OS}"
OUT="build/release"

swift package resolve
GENERATE_APPCAST="$(find .build/artifacts -type f -name generate_appcast 2>/dev/null | head -1)"
if [[ -z "$GENERATE_APPCAST" ]]; then
  echo "❌ ไม่พบเครื่องมือของ Sparkle ใน .build/artifacts" >&2
  exit 1
fi
TOOLS="$(dirname "$GENERATE_APPCAST")"

if ! "$TOOLS/generate_keys" -p >/dev/null 2>&1; then
  echo "▶ ยังไม่มีกุญแจเซ็นอัปเดต กำลังสร้างและเก็บไว้ใน Keychain…"
  "$TOOLS/generate_keys"
  echo "⚠️  สำรองกุญแจไว้ด้วย: $TOOLS/generate_keys -x ~/linmo-sparkle-private-key — ถ้ากุญแจหาย แอพที่ติดตั้งไปแล้วจะรับอัปเดตไม่ได้อีก"
fi
SPARKLE_PUBLIC_KEY="$("$TOOLS/generate_keys" -p)"
export SPARKLE_PUBLIC_KEY

./scripts/build-app.sh release

PLIST="build/LinMO.app/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
TAG="v$VERSION"

rm -rf "$OUT"
mkdir -p "$OUT"
ditto -c -k --sequesterRsrc --keepParent build/LinMO.app "$OUT/LinMO-$VERSION.zip"

if curl -fsSL "https://github.com/$REPO/releases/latest/download/appcast.xml" -o "$OUT/appcast.xml"; then
  if grep -q "<sparkle:version>$BUILD</sparkle:version>" "$OUT/appcast.xml"; then
    echo "❌ build $BUILD มีใน appcast แล้ว — เพิ่ม CFBundleVersion ใน Resources/Info.plist ก่อน" >&2
    exit 1
  fi
else
  rm -f "$OUT/appcast.xml"
fi

"$TOOLS/generate_appcast" --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" "$OUT"

echo "✅ ได้ไฟล์แล้ว: $OUT/LinMO-$VERSION.zip และ $OUT/appcast.xml"

if [[ "$PUBLISH" == "--publish" ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "❌ ไม่พบคำสั่ง gh (brew install gh แล้ว gh auth login)" >&2
    exit 1
  fi
  gh release create "$TAG" "$OUT/LinMO-$VERSION.zip" "$OUT/appcast.xml" \
    --repo "$REPO" --title "LinMO $VERSION" --generate-notes
  echo "✅ ปล่อย $TAG แล้ว แอพที่ติดตั้งไว้จะเห็นรุ่นใหม่ตอนตรวจครั้งถัดไป"
else
  echo "ℹ️  อัปโหลดสองไฟล์นี้ขึ้น GitHub Release ชื่อ $TAG เอง หรือรัน ./scripts/release.sh --publish"
fi
