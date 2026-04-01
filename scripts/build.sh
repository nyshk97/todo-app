#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$REPO_ROOT/apps/macos"
BUILD_DIR="$REPO_ROOT/build"

# プロジェクト生成
bash "$REPO_ROOT/scripts/generate-projects.sh"

# クリーンビルド（署名なし）
cd "$APP_DIR"
xcodebuild build \
  -project TodoMac.xcodeproj \
  -scheme TodoMac \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/derived" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  -quiet

# zip 化
APP_PATH="$BUILD_DIR/derived/Build/Products/Release/TodoMac.app"
cd "$(dirname "$APP_PATH")"
zip -r "$BUILD_DIR/TodoMac.zip" TodoMac.app

# SHA256
echo ""
echo "✅ Build complete: $BUILD_DIR/TodoMac.zip"
echo "SHA256: $(shasum -a 256 "$BUILD_DIR/TodoMac.zip" | awk '{print $1}')"
