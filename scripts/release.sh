#!/bin/bash
# TodoMac リリーススクリプト
# 使い方: ./scripts/release.sh [patch|minor|major|<x.y.z>]   （省略時は patch）
#
# 0. 事前チェック（clean worktree / origin/main と一致 / gh 認証 / タグ・Release の重複 /
#    CHANGELOG の [Unreleased] / 画面ロック / 署名証明書 / notarize 資格情報 / Sparkle 鍵）
# 1. apps/todo/macos/project.yml の MARKETING_VERSION を bump（CURRENT_PROJECT_VERSION は
#    タイムスタンプ）し、CHANGELOG の [Unreleased] を [<version>] - <date> に切り出して同じ commit に
# 2. build.sh でビルド + 署名 + notarize + staple + 配布 ZIP の検証
# 3. zip に Sparkle の EdDSA 署名を付けて build/appcast.xml を生成（CHANGELOG を <description> に）
# 4. bump commit を main に push
# 5. GitHub Release（v<version>）を作成し zip と appcast.xml を添付（ノートは CHANGELOG から）
# 6. nyshk97/homebrew-tap の Casks/todo-mac.rb を更新 → ローカル tap を同期
#
# notarize（失敗しやすく数分かかる工程）を push より前に置く。bump はビルド前にローカルで commit し、
# push までに失敗したら trap がその commit を巻き戻す（remote も作業ツリーも実行前の状態に戻る）。
# Claude Code のセッションから叩いてよい。唯一の条件は submit の数分間に画面がロックされないこと
# （notarytool の資格情報は data-protection keychain にあり、ロック中は読めない）。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="TodoMac"
BUILD_DIR="$REPO_ROOT/build"
ZIP_FILE="$BUILD_DIR/TodoMac.zip"
PROJECT_YML="$REPO_ROOT/apps/todo/macos/project.yml"
CHANGELOG="$REPO_ROOT/apps/todo/macos/CHANGELOG.md"
CHANGELOG_PY="$REPO_ROOT/scripts/changelog.py"
GITHUB_REPO="nyshk97/todo-app"
TAP_REPO="nyshk97/homebrew-tap"
CASK_TOKEN="todo-mac"
CASK_PATH="Casks/${CASK_TOKEN}.rb"
TEAM_ID="VYDUR99LAM"
NOTARY_PROFILE="${NOTARY_PROFILE:-nyshk97-notary}"
SPARKLE_ACCOUNT="todo-mac"
SIGN_UPDATE="$BUILD_DIR/derived/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
APPCAST="$BUILD_DIR/appcast.xml"
# アプリが見に行く feed。build.sh が成果物の SUFeedURL と突き合わせる。
export FEED_URL="https://github.com/$GITHUB_REPO/releases/latest/download/appcast.xml"
STAGE_DIR=""

cleanup() {
  if [ -n "$STAGE_DIR" ]; then rm -rf "$STAGE_DIR" 2>/dev/null || true; fi
}
trap cleanup EXIT

# ===== バージョン計算 =====
CURRENT_VERSION="$(grep -m1 'MARKETING_VERSION:' "$PROJECT_YML" | sed 's/.*MARKETING_VERSION: *//' | tr -d '"' | tr -d ' ')"
[ -n "$CURRENT_VERSION" ] || { echo "❌ project.yml から MARKETING_VERSION を取れません"; exit 1; }
BUMP="${1:-patch}"
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
case "$BUMP" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
  [0-9]*.[0-9]*.[0-9]*) IFS='.' read -r MAJOR MINOR PATCH <<< "$BUMP" ;;
  *) echo "❌ 不正なバージョン指定: ${BUMP}（patch|minor|major|x.y.z）"; exit 1 ;;
esac
VERSION="$MAJOR.$MINOR.$PATCH"
BUILD_NUMBER="$(date +%Y%m%d%H%M%S)"
TAG="v$VERSION"
echo "現在のバージョン: ${CURRENT_VERSION} → 新しいバージョン: ${VERSION} (build ${BUILD_NUMBER})"

# ===== 事前チェック =====
# ビルド + notarize は数分かかる。先に見ておかないと、それを終えてから落ちる。
if [ -n "$(git status --porcelain)" ]; then
  echo "❌ 作業ツリーに未コミットの変更があります。コミットしてから実行してください。"
  git status --short
  exit 1
fi
# 複数マシンで開発しているので、ローカルの main は別クローンからのリリースで平気で遅れる。
git fetch -q origin --tags
if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
  echo "❌ HEAD が origin/main と一致しません（pull 忘れ / push 忘れ）。"
  echo "   local : $(git rev-parse --short HEAD)"
  echo "   origin: $(git rev-parse --short origin/main)"
  exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "❌ gh が未認証です。gh auth login を先に済ませてください。"
  exit 1
fi
# タグ・リリースの重複はリモートに問い合わせる。
if gh release view "$TAG" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
  echo "❌ リリース $TAG は既に存在します。"
  exit 1
fi
if [ -n "$(git ls-remote --tags origin "refs/tags/$TAG")" ]; then
  echo "❌ タグ $TAG は既にリモートにあります。"
  exit 1
fi
# リリースノートは CHANGELOG の [Unreleased] からしか作らない。空なら止める
python3 "$CHANGELOG_PY" check
# 画面ロック中は notarytool の資格情報が読めない。submit に数分かかるので始める前に止める
CONSOLE_LOCKED="$(ioreg -n Root -d1 -a 2>/dev/null | plutil -extract IOConsoleLocked raw -o - - 2>/dev/null || true)"
if [ "$CONSOLE_LOCKED" = "true" ]; then
  echo "❌ 画面がロックされています。解除してから実行してください。"
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
  echo "   未作成なら: xcrun notarytool store-credentials $NOTARY_PROFILE \\"
  echo "     --key ~/Library/CloudStorage/Dropbox/secrets/AuthKey_M4FG2B8JFX.p8 \\"
  echo "     --key-id M4FG2B8JFX --issuer 024fc873-10f9-49a4-8d6f-20fb5c7bd522"
  exit 1
fi
if ! security find-generic-password -s "https://sparkle-project.org" -a "$SPARKLE_ACCOUNT" >/dev/null 2>&1; then
  echo "❌ Sparkle の EdDSA 秘密鍵（keychain account '$SPARKLE_ACCOUNT'）がありません。"
  echo "   復元: build/derived/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account $SPARKLE_ACCOUNT -f ~/Library/CloudStorage/Dropbox/secrets/sparkle-ed25519-todo-mac-private.key"
  exit 1
fi

# ===== バージョン更新 + CHANGELOG 切り出し（ローカル commit。push は notarize 後）=====
sed -i '' "s/MARKETING_VERSION: \".*\"/MARKETING_VERSION: \"$VERSION\"/" "$PROJECT_YML"
sed -i '' "s/CURRENT_PROJECT_VERSION: \".*\"/CURRENT_PROJECT_VERSION: \"$BUILD_NUMBER\"/" "$PROJECT_YML"
python3 "$CHANGELOG_PY" release "$VERSION" "$(date +%Y-%m-%d)"
git add "$PROJECT_YML" "$CHANGELOG"
git commit -q -m "chore: bump macOS app version to $VERSION"
BUMP_PUSHED=0
rollback_bump() {
  if [ "$BUMP_PUSHED" -eq 0 ]; then
    echo "↩️  失敗したので bump commit を巻き戻します（remote は未変更）"
    git reset -q --hard HEAD~1
  fi
}
trap 'rollback_bump' ERR

# ===== ビルド + 署名 + notarize（remote 反映前に実施）=====
bash "$REPO_ROOT/scripts/build.sh"

[ -f "$ZIP_FILE" ] || { echo "❌ 配布 zip が見つかりません: $ZIP_FILE"; exit 1; }

# ===== 公開直前ガード =====
# build.sh 内でも検証しているが、公開するバイトそのものをもう一度見る。
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
APP_BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$STAGED_APP/Contents/Info.plist")"
if [ "$APP_BUILD" != "$BUILD_NUMBER" ]; then
  echo "❌ CFBundleVersion ($APP_BUILD) がビルド番号 ($BUILD_NUMBER) と一致しません（Sparkle の新旧比較が壊れる）。"
  exit 1
fi
SHA256=$(shasum -a 256 "$ZIP_FILE" | awk '{print $1}')

# ===== Sparkle: EdDSA 署名 + appcast =====
[ -x "$SIGN_UPDATE" ] || { echo "❌ sign_update が見つかりません: $SIGN_UPDATE"; exit 1; }
echo "🔏 Sparkle の EdDSA 署名を付けています..."
ED_ATTRS="$("$SIGN_UPDATE" --account "$SPARKLE_ACCOUNT" "$ZIP_FILE")"   # sparkle:edSignature="..." length="..."
case "$ED_ATTRS" in
  *sparkle:edSignature=*) ;;
  *) echo "❌ sign_update の出力が想定外です: $ED_ATTRS"; exit 1 ;;
esac
RELEASE_NOTES_MD="$BUILD_DIR/release-notes-$VERSION.md"
SPARKLE_DESC_HTML="$BUILD_DIR/sparkle-description-$VERSION.html"
python3 "$CHANGELOG_PY" notes "$VERSION" "$RELEASE_NOTES_MD" "$SPARKLE_DESC_HTML"
PUBDATE="$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")"
DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/$TAG/TodoMac.zip"
RELEASE_URL="https://github.com/$GITHUB_REPO/releases/tag/$TAG"
# 1 item だけでよい: feed は releases/latest/download/appcast.xml で常に最新 Release の物を指す。
# sparkle:version は CFBundleVersion（タイムスタンプ）。Sparkle の新旧比較はこちらで行われる。
cat > "$APPCAST" <<APPCAST_EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>$APP_NAME</title>
    <item>
      <title>$TAG</title>
      <pubDate>$PUBDATE</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>$RELEASE_URL</sparkle:fullReleaseNotesLink>
      <description><![CDATA[
$(cat "$SPARKLE_DESC_HTML")
]]></description>
      <enclosure url="$DOWNLOAD_URL" $ED_ATTRS type="application/octet-stream"/>
    </item>
  </channel>
</rss>
APPCAST_EOF
xmllint --noout "$APPCAST"

# ===== push =====
git push origin main
BUMP_PUSHED=1
trap - ERR

# ===== GitHub Release =====
echo "🚀 GitHub Release を作成中..."
gh release create "$TAG" "$ZIP_FILE" "$APPCAST" \
  --repo "$GITHUB_REPO" \
  --title "$TAG" \
  --notes-file "$RELEASE_NOTES_MD"

# ===== Cask 更新 =====
echo "🍺 Cask $CASK_PATH を更新中..."
CASK_CONTENT=$(cat <<CASK
cask "$CASK_TOKEN" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/$GITHUB_REPO/releases/download/v#{version}/TodoMac.zip"
  name "$APP_NAME"
  homepage "https://github.com/$GITHUB_REPO"

  auto_updates true

  app "TodoMac.app"
end
CASK
)
ENCODED=$(printf '%s' "$CASK_CONTENT" | base64)
EXISTING_SHA=$(gh api "repos/$TAP_REPO/contents/$CASK_PATH" --jq '.sha' 2>/dev/null || true)
if [ -n "$EXISTING_SHA" ]; then
  gh api "repos/$TAP_REPO/contents/$CASK_PATH" --method PUT \
    --field message="chore: bump $CASK_TOKEN to $VERSION" --field content="$ENCODED" --field sha="$EXISTING_SHA" --silent
else
  gh api "repos/$TAP_REPO/contents/$CASK_PATH" --method PUT \
    --field message="feat: add $CASK_TOKEN $VERSION" --field content="$ENCODED" --silent
fi

# ===== ローカル tap 同期 =====
TAP_DIR="$(brew --repository "$TAP_REPO" 2>/dev/null || true)"
if [ -d "$TAP_DIR/.git" ]; then
  git -C "$TAP_DIR" pull --ff-only origin main --quiet || true
fi

echo ""
echo "✅ リリース完了: $TAG"
echo "   release: $RELEASE_URL"
echo "   sha256 : $SHA256"
echo "   feed   : $FEED_URL"
echo "   cask   : $TAP_REPO $CASK_PATH"
