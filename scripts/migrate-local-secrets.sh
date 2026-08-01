#!/bin/bash
# 2026-08-01 のモノレポ統合に伴い、git 管理外の設定ファイルを旧パスから新パスへ移す。
# 統合前から clone を持っていた環境で1回だけ実行する（何度実行してもよい）。
#
#   bash scripts/migrate-local-secrets.sh [<旧 todo-shelf clone のパス>]
#
# - git は gitignore 対象のファイルを移動・削除しないため、pull 後も旧パスに残っている
# - 新パスに既にファイルがあれば上書きしない
# - 秘密の値そのものは表示しない

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

SHELF_SRC="${1:-$HOME/todo-shelf}"

moved=0
skipped=0
notfound=0

report_ok()   { printf '  \033[32m%s\033[0m %s\n         → %s\n' "${3:-移動}" "$1" "$2"; moved=$((moved + 1)); }
report_skip() { printf '  \033[33mスキップ\033[0m %s（既に存在）\n' "$1"; skipped=$((skipped + 1)); }
report_none() { printf '  \033[31m見つからない\033[0m %s\n         元: %s\n' "$1" "$2"; notfound=$((notfound + 1)); }

# take <元パス> <先パス> <mv|cp>
take() {
  local src="$1" dst="$2" mode="$3"
  if [ -s "$dst" ]; then report_skip "$dst"; return; fi
  if [ ! -s "$src" ]; then report_none "$dst" "$src"; return; fi
  mkdir -p "$(dirname "$dst")"
  if [ "$mode" = mv ]; then mv "$src" "$dst"; else cp "$src" "$dst"; fi
  report_ok "$src" "$dst" "$([ "$mode" = mv ] && echo 移動 || echo コピー)"
}

echo "== todo: リポジトリ内の旧パスから移動 =="
take apps/api/.dev.vars   apps/todo/api/.dev.vars   mv
take apps/ios/.env        apps/todo/ios/.env        mv
take apps/macos/.env      apps/todo/macos/.env      mv

echo
echo "== shelf: 旧 todo-shelf clone からコピー =="
# 変数展開の直後に全角文字を置くと bash が変数名の一部として読むので必ず ${} で囲む
echo "   （元: ${SHELF_SRC}）"
if [ -d "$SHELF_SRC" ]; then
  take "$SHELF_SRC/apps/api/.dev.vars"       apps/shelf/api/.dev.vars       cp
  take "$SHELF_SRC/apps/web/.env"            apps/shelf/web/.env            cp
  take "$SHELF_SRC/apps/web/.env.production" apps/shelf/web/.env.production cp

  # shelf iOS の .env は旧 clone に存在しない（当時は Secrets.swift を手書きしていた）。
  # Secrets.swift の API_SECRET と todo 側の DEVELOPMENT_TEAM から組み立てる。
  shelf_secrets="$SHELF_SRC/apps/ios/Sources/Secrets.swift"
  if [ -s apps/shelf/ios/.env ]; then
    report_skip apps/shelf/ios/.env
  elif [ -s "$shelf_secrets" ] && [ -s apps/todo/ios/.env ]; then
    api_secret="$(sed -n 's/.*apiSecret *= *"\(.*\)".*/\1/p' "$shelf_secrets" | head -1)"
    dev_team="$(sed -n 's/^DEVELOPMENT_TEAM=//p' apps/todo/ios/.env | head -1)"
    if [ -n "$api_secret" ] && [ -n "$dev_team" ]; then
      printf 'DEVELOPMENT_TEAM=%s\nAPI_SECRET=%s\n' "$dev_team" "$api_secret" > apps/shelf/ios/.env
      report_ok "$shelf_secrets + apps/todo/ios/.env" apps/shelf/ios/.env 生成
    else
      report_none apps/shelf/ios/.env "値を抽出できなかった（$shelf_secrets / apps/todo/ios/.env）"
    fi
  else
    report_none apps/shelf/ios/.env "$shelf_secrets"
  fi
else
  echo "  旧 clone が見つかりません。パスを引数で渡してください:"
  echo "    bash scripts/migrate-local-secrets.sh /path/to/todo-shelf"
  notfound=$((notfound + 4))
fi

echo
echo "== 結果: 移動 $moved / スキップ $skipped / 未解決 $notfound =="

# 旧ディレクトリの残骸を報告（削除はしない）
leftovers=""
for d in apps/api apps/ios apps/macos packages/shared; do
  [ -d "$d" ] && leftovers="$leftovers $d"
done
if [ -n "$leftovers" ]; then
  echo
  echo "統合前のディレクトリが残っています（中身は再生成可能な .xcodeproj / Secrets.swift 等のはず）。"
  echo "上の確認が通ったら手で消してください:"
  echo "   rm -rf$leftovers"
fi

echo
bash "$REPO_ROOT/scripts/check-setup.sh"
