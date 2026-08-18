#!/bin/bash
# TodoMac リリーススクリプト
# 使い方: ./scripts/release.sh <version>
#
# 1. 事前チェック（作業ツリー / gh 認証 / タグ重複 / 署名証明書 / notarize 資格情報）
# 2. project.yml の MARKETING_VERSION を更新
# 3. build.sh でビルド + 署名 + notarize + staple + 配布 ZIP の検証
# 4. バージョン更新を commit して main に push
# 5. GitHub Release（v<version>）を作成し zip を添付
# 6. nyshk97/homebrew-tap の Casks/todo-mac.rb を更新 → ローカル tap を同期
#
# notarize（失敗しやすく数分かかる工程）を push より前に置く。失敗時は project.yml の
# 変更がローカルに残るだけで remote には何も反映されない
# （`git checkout apps/todo/macos/project.yml` で戻せる）。
#
# 実行はユーザーの Terminal から。notarize 中に画面がロックされると
# 「プロファイルが無い」で落ちる（資格情報が data-protection keychain にあるため）。
set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version>"
  echo "Example: $0 1.0.0"
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

BUILD_DIR="$REPO_ROOT/build"
ZIP_FILE="$BUILD_DIR/TodoMac.zip"
PROJECT_YML="$REPO_ROOT/apps/todo/macos/project.yml"
GITHUB_REPO="nyshk97/todo-app"
TAP_REPO="nyshk97/homebrew-tap"
CASK_PATH="Casks/todo-mac.rb"
TEAM_ID="VYDUR99LAM"
NOTARY_PROFILE="${NOTARY_PROFILE:-nyshk97-notary}"
TAG="v$VERSION"
STAGE_DIR=""

cleanup() {
  if [ -n "$STAGE_DIR" ]; then rm -rf "$STAGE_DIR" 2>/dev/null || true; fi
}
trap cleanup EXIT

# ===== 事前チェック =====
# ビルド + notarize は数分かかる。先に見ておかないと、それを終えてから落ちて
# bump 済みの project.yml が中途半端に残る。
if [ -n "$(git status --porcelain)" ]; then
  echo "❌ 作業ツリーに未コミットの変更があります。コミットしてから実行してください。"
  git status --short
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "❌ gh が未認証です。gh auth login を先に済ませてください。"
  exit 1
fi

# タグ・リリースの重複はリモートに問い合わせる。ローカルタグは別マシンの古い状態が
# 残っていることがあり、あてにならない。
if gh release view "$TAG" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
  echo "❌ リリース $TAG は既に存在します。"
  exit 1
fi
if [ -n "$(git ls-remote --tags origin "refs/tags/$TAG")" ]; then
  echo "❌ タグ $TAG は既にリモートにあります。"
  exit 1
fi

IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
case "$IDENTITIES" in
  *"Developer ID Application"*"($TEAM_ID)"*) ;;
  *) echo "❌ Developer ID Application 証明書（${TEAM_ID}）が keychain にありません。"
     echo "   Xcode → Settings → Accounts → Manage Certificates から取得してください。"
     exit 1 ;;
esac

if ! NOTARY_CHECK="$(xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" 2>&1)"; then
  echo "❌ notarize の keychain プロファイル '$NOTARY_PROFILE' が使えません:"
  echo "$NOTARY_CHECK" | head -3
  echo "   画面がロックされていると資格情報が見えなくなります（解除すれば直る）:"
  echo "     ioreg -n Root -d1 -a | plutil -extract IOConsoleLocked xml1 -o - -"
  echo "   未作成なら: xcrun notarytool store-credentials $NOTARY_PROFILE \\"
  echo "     --key ~/Library/CloudStorage/Dropbox/secrets/AuthKey_M4FG2B8JFX.p8 \\"
  echo "     --key-id M4FG2B8JFX --issuer 024fc873-10f9-49a4-8d6f-20fb5c7bd522"
  exit 1
fi

# ===== バージョン更新 =====
sed -i '' "s/MARKETING_VERSION: \".*\"/MARKETING_VERSION: \"$VERSION\"/" "$PROJECT_YML"

# ===== ビルド + 署名 + notarize（remote 反映前に実施）=====
bash "$REPO_ROOT/scripts/build.sh"

[ -f "$ZIP_FILE" ] || { echo "❌ 配布 zip が見つかりません: $ZIP_FILE"; exit 1; }

# ===== 公開直前ガード =====
# build.sh 内でも検証しているが、公開するバイトそのものをもう一度見る。
# stapler validate は spctl と違って staple ticket の存在を直接確認できる。
echo "🔎 公開前の最終確認..."
STAGE_DIR="$(mktemp -d)"
ditto -x -k "$ZIP_FILE" "$STAGE_DIR"
STAGED_APP="$STAGE_DIR/TodoMac.app"
xcrun stapler validate "$STAGED_APP"

APP_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$STAGED_APP/Contents/Info.plist")"
if [ "$APP_VERSION" != "$VERSION" ]; then
  echo "❌ アプリ内バージョン ($APP_VERSION) と指定バージョン ($VERSION) が一致しません。"
  exit 1
fi

SHA256=$(shasum -a 256 "$ZIP_FILE" | awk '{print $1}')

# ===== commit + push =====
if ! git diff --quiet "$PROJECT_YML"; then
  git add "$PROJECT_YML"
  git commit -m "chore: bump macOS app version to $VERSION"
  git push origin main
fi

# ===== リリースノート =====
# todo 配下の変更だけから作る。モノレポ化で shelf のコミットも v* タグ間に入るため、
# --generate-notes だと TodoMac と無関係な履歴が大量に混入する
# （v1.17.1 時点で 64 件中 48 件が shelf）。
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

# ===== GitHub Release =====
gh release create "$TAG" "$ZIP_FILE" \
  --repo "$GITHUB_REPO" \
  --title "$TAG" \
  --notes "$NOTES"

# ===== Cask 更新 =====
CASK_CONTENT=$(cat <<CASK
cask "todo-mac" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/$GITHUB_REPO/releases/download/v#{version}/TodoMac.zip"
  name "TodoMac"
  homepage "https://github.com/$GITHUB_REPO"

  app "TodoMac.app"
end
CASK
)

ENCODED=$(echo "$CASK_CONTENT" | base64)
FILE_SHA=$(gh api "repos/$TAP_REPO/contents/$CASK_PATH" --jq '.sha')

gh api "repos/$TAP_REPO/contents/$CASK_PATH" \
  --method PUT \
  --field message="chore: bump todo-mac to $VERSION" \
  --field content="$ENCODED" \
  --field sha="$FILE_SHA" \
  --silent

# ===== ローカル tap 同期 =====
# brew のローカル tap クローンは自動更新されないので、ここで pull しておかないと
# 直後の `brew bundle` が「No available formula or cask」になる。
TAP_DIR="$(brew --repository "$TAP_REPO" 2>/dev/null || true)"
if [ -d "$TAP_DIR/.git" ]; then
  git -C "$TAP_DIR" pull --ff-only origin main --quiet || true
fi

echo ""
echo "✅ Released $TAG"
echo "   sha256: $SHA256"
echo "✅ homebrew-tap updated & synced"
