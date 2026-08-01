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
sed -i '' "s/MARKETING_VERSION: \".*\"/MARKETING_VERSION: \"$VERSION\"/" "$REPO_ROOT/apps/todo/macos/project.yml"

# バージョン更新をコミット
cd "$REPO_ROOT"
if ! git diff --quiet apps/todo/macos/project.yml; then
  git add apps/todo/macos/project.yml
  git commit -m "chore: bump macOS app version to $VERSION"
  git push origin main
fi

# ビルド（常に再ビルド）
rm -rf "$BUILD_DIR"
bash "$REPO_ROOT/scripts/build.sh"

# リリースノートは todo 配下の変更だけから作る。
# モノレポ化で shelf のコミットも v* タグ間に入るため、--generate-notes だと
# TodoMac と無関係な履歴が大量に混入する（v1.17.1 時点で 64 件中 48 件が shelf）。
PREV_TAG="$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"
# pathspec は各コミット当時のパスに対して評価されるため、
# scripts/shelf/ へ移す前の旧パスも除外しないと過去の shelf コミットが残る
TODO_PATHS=(
  apps/todo
  packages/todo-shared
  scripts
  ':(exclude)scripts/shelf'
  ':(exclude)scripts/migrate-from-todoist.ts'
)
if [ -n "$PREV_TAG" ]; then
  NOTES="$(git log --no-merges --pretty='- %s' "$PREV_TAG..HEAD" -- "${TODO_PATHS[@]}")"
else
  NOTES="$(git log --no-merges --pretty='- %s' -20 -- "${TODO_PATHS[@]}")"
fi
if [ -z "$NOTES" ]; then
  NOTES="- メンテナンスリリース"
fi

# GitHub Release 作成
gh release create "v$VERSION" "$ZIP_FILE" \
  --repo nyshk97/todo-app \
  --title "v$VERSION" \
  --notes "$NOTES"

SHA256=$(shasum -a 256 "$ZIP_FILE" | awk '{print $1}')

# homebrew-tap の Cask を更新
CASK_CONTENT=$(cat <<CASK
cask "todo-mac" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/nyshk97/todo-app/releases/download/v#{version}/TodoMac.zip"
  name "TodoMac"
  homepage "https://github.com/nyshk97/todo-app"

  app "TodoMac.app"
end
CASK
)

ENCODED=$(echo "$CASK_CONTENT" | base64)
FILE_SHA=$(gh api repos/nyshk97/homebrew-tap/contents/Casks/todo-mac.rb --jq '.sha')

gh api repos/nyshk97/homebrew-tap/contents/Casks/todo-mac.rb \
  --method PUT \
  --field message="chore: bump todo-mac to $VERSION" \
  --field content="$ENCODED" \
  --field sha="$FILE_SHA" \
  --silent

# ローカルの tap を同期
TAP_DIR="$(brew --repository nyshk97/homebrew-tap 2>/dev/null || true)"
if [ -d "$TAP_DIR/.git" ]; then
  git -C "$TAP_DIR" pull --ff-only origin main --quiet
fi

echo ""
echo "✅ Released v$VERSION"
echo "✅ homebrew-tap updated & synced"
