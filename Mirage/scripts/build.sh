#!/bin/bash
set -euo pipefail

CONFIG="${1:-Release}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="$(cd "$HERE/.." && pwd)"
ROOT="$(cd "$PROJ_DIR/.." && pwd)"
BUILD_DIR="$PROJ_DIR/build"
PROJECT="$PROJ_DIR/Mirage Wallpaper.xcodeproj"
SCHEME="Mirage Wallpaper"

echo "[build] 编译 ($CONFIG)..."
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
    -destination 'platform=macOS' \
    -derivedDataPath "$BUILD_DIR/DD" \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
    build | tail -3

APP="$BUILD_DIR/DD/Build/Products/$CONFIG/Mirage Wallpaper.app"
[ -d "$APP" ] || { echo "[build] 未找到产物: $APP" >&2; exit 1; }

echo "[build] 内嵌渲染器与依赖..."
bash "$HERE/bundle_renderers.sh" "$APP" "$ROOT"

OUT="$PROJ_DIR/dist"
mkdir -p "$OUT"
rm -rf "$OUT/Mirage.app"
cp -R "$APP" "$OUT/Mirage.app"
codesign --force --deep --sign - "$OUT/Mirage.app" 2>/dev/null || true

echo "[build] 完成  产物: $OUT/Mirage.app"
