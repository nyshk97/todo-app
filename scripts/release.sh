#!/bin/bash
set -e

VERSION="$1"
if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version>"
  echo "Example: $0 1.0.0"
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"
ZIP_FILE="$BUILD_DIR/TodoMac.zip"

# MARKETING_VERSION を更新
sed -i '' "s/MARKETING_VERSION: \".*\"/MARKETING_VERSION: \"$VERSION\"/" "$REPO_ROOT/apps/macos/project.yml"

# バージョン更新をコミット
cd "$REPO_ROOT"
if ! git diff --quiet apps/macos/project.yml; then
  git add apps/macos/project.yml
  git commit -m "chore: bump macOS app version to $VERSION"
  git push origin main
fi

# ビルド（常に再ビルド）
rm -rf "$BUILD_DIR"
bash "$REPO_ROOT/scripts/build.sh"

# GitHub Release 作成
gh release create "v$VERSION" "$ZIP_FILE" \
  --repo nyshk97/todo-app \
  --title "v$VERSION" \
  --generate-notes

SHA256=$(shasum -a 256 "$ZIP_FILE" | awk '{print $1}')

echo ""
echo "✅ Released v$VERSION"
echo ""
echo "Update homebrew-tap Casks/todo-mac.rb:"
echo "  version \"$VERSION\""
echo "  sha256 \"$SHA256\""
