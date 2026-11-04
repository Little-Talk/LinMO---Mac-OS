#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

MODE="${1:-release}"
RUN_AFTER="${2:-}"
APP="build/LinMO.app"
ENTITLEMENTS="Resources/LinMO.entitlements"
CONFIG="$MODE"
case "$MODE" in
  sandbox|appstore)
    CONFIG="release"
    ENTITLEMENTS="Resources/LinMO-AppStore.entitlements"
    ;;
esac

SPARKLE=1
BUILD_ARGS=(-c "$CONFIG" --arch arm64)
case "$MODE" in
  sandbox|appstore)
    SPARKLE=0
    export LINMO_NO_SPARKLE=1
    BUILD_ARGS+=(--build-path .build-nosparkle)
    ;;
esac
FEED_URL="${SPARKLE_FEED_URL:-https://github.com/Little-Talk/LinMO---Mac-OS/releases/latest/download/appcast.xml}"

if [[ "$MODE" == "appstore" ]]; then
  for var in SIGN_IDENTITY INSTALLER_IDENTITY TEAM_ID PROVISIONING_PROFILE; do
    if [[ -z "${!var:-}" ]]; then
      echo "❌ รุ่น appstore ต้องตั้งตัวแปร $var (ดู docs/APP_STORE.md)" >&2
      exit 1
    fi
  done
fi

if command -v python3 >/dev/null 2>&1; then
  python3 scripts/embed-guest-files.py
fi

echo "▶ กำลัง build ($CONFIG)…"
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"

echo "▶ กำลังประกอบ ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/LinMO" "$APP/Contents/MacOS/LinMO"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/PrivacyInfo.xcprivacy "$APP/Contents/Resources/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

if [[ "$SPARKLE" == "1" ]]; then
  mkdir -p "$APP/Contents/Frameworks"
  ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/LinMO" 2>/dev/null || true
  PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-}"
  if [[ -z "$PUBLIC_KEY" ]]; then
    GENERATE_KEYS="$(find .build/artifacts -type f -name generate_keys 2>/dev/null | head -1)"
    if [[ -n "$GENERATE_KEYS" ]]; then
      PUBLIC_KEY="$("$GENERATE_KEYS" -p 2>/dev/null || true)"
    fi
  fi
  /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $FEED_URL" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool true" "$APP/Contents/Info.plist"
  if [[ -n "$PUBLIC_KEY" ]]; then
    /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $PUBLIC_KEY" "$APP/Contents/Info.plist"
  else
    echo "ℹ️  ยังไม่มีกุญแจ Sparkle ใน Keychain — แอพนี้จะไม่มีเมนูตรวจหาอัปเดต (รัน scripts/release.sh เพื่อสร้างกุญแจ)"
  fi
fi
if xcrun --find actool >/dev/null 2>&1; then
  xcrun actool Resources/AppIcon.xcassets \
    --compile "$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist build/AppIcon-partial.plist >/dev/null
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AppIcon" "$APP/Contents/Info.plist"
else
  echo "ℹ️  ไม่พบ actool (ต้องมี Xcode) — ใช้ AppIcon.icns อย่างเดียว"
fi
if [[ -f guest/bin/linmo-wayland-aarch64 ]]; then
  cp guest/bin/linmo-wayland-aarch64 "$APP/Contents/Resources/"
else
  echo "ℹ️  ยังไม่มี guest/bin/linmo-wayland-aarch64 — เครื่อง Linux จะสร้างจากซอร์สโค้ดเองถ้าทำได้"
fi

SIGN_ENTITLEMENTS="$ENTITLEMENTS"
if [[ "$MODE" == "appstore" ]]; then
  cp "$PROVISIONING_PROFILE" "$APP/Contents/embedded.provisionprofile"
  BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Resources/Info.plist)"
  SIGN_ENTITLEMENTS="build/LinMO-AppStore.entitlements"
  cp "$ENTITLEMENTS" "$SIGN_ENTITLEMENTS"
  /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $TEAM_ID.$BUNDLE_ID" "$SIGN_ENTITLEMENTS"
  /usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$SIGN_ENTITLEMENTS"
fi

if [[ "$SPARKLE" == "1" ]]; then
  if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    SIGN_ENTITLEMENTS="build/LinMO-adhoc.entitlements"
    cp "$ENTITLEMENTS" "$SIGN_ENTITLEMENTS"
    /usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$SIGN_ENTITLEMENTS"
  fi
  SPARKLE_DIR="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
  for item in "$SPARKLE_DIR/XPCServices/Installer.xpc" "$SPARKLE_DIR/Autoupdate" "$SPARKLE_DIR/Updater.app"; do
    if [[ -e "$item" ]]; then
      codesign --force --sign "${SIGN_IDENTITY:--}" --options runtime "$item"
    fi
  done
  if [[ -e "$SPARKLE_DIR/XPCServices/Downloader.xpc" ]]; then
    codesign --force --sign "${SIGN_IDENTITY:--}" --options runtime --preserve-metadata=entitlements "$SPARKLE_DIR/XPCServices/Downloader.xpc"
  fi
  codesign --force --sign "${SIGN_IDENTITY:--}" --options runtime "$APP/Contents/Frameworks/Sparkle.framework"
fi

echo "▶ กำลังเซ็นแอพ ($SIGN_ENTITLEMENTS)…"
codesign --force \
  --sign "${SIGN_IDENTITY:--}" \
  --entitlements "$SIGN_ENTITLEMENTS" \
  --options runtime \
  "$APP"

if [[ "$MODE" == "appstore" ]]; then
  echo "▶ กำลังสร้าง build/LinMO.pkg…"
  productbuild --component "$APP" /Applications --sign "$INSTALLER_IDENTITY" build/LinMO.pkg
  echo "✅ เสร็จแล้ว: build/LinMO.pkg — อัปโหลดด้วยแอพ Transporter หรือ xcrun altool"
  exit 0
fi

echo "✅ เสร็จแล้ว: $APP"

if [[ "$RUN_AFTER" == "--run" ]]; then
  open "$APP"
fi
