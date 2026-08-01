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

done_count=0
skipped=0
notfound=0
failed=0

report_ok()   { printf '  \033[32m%s\033[0m %s\n         → %s\n' "${3:-移動}" "$1" "$2"; done_count=$((done_count + 1)); }
report_skip() { printf '  \033[33mスキップ\033[0m %s（既に存在）\n' "$1"; skipped=$((skipped + 1)); }
report_none() { printf '  \033[31m見つからない\033[0m %s\n         元: %s\n' "$1" "$2"; notfound=$((notfound + 1)); }
report_fail() { printf '  \033[31m失敗\033[0m %s\n         元: %s（%s）\n' "$1" "$2" "$3"; failed=$((failed + 1)); }

# take <元パス> <先パス> <mv|cp>
# コピー系は一時ファイルに書いてサイズを検証してから rename する。
# 失敗を黙って握りつぶすと「✅ 揃っています」と誤報告してしまうため、
# 成否を必ず判定して失敗件数に数える。
take() {
  local src="$1" dst="$2" mode="$3" label tmp
  label="$([ "$mode" = mv ] && echo 移動 || echo コピー)"

  if [ -s "$dst" ]; then report_skip "$dst"; return; fi
  if [ ! -s "$src" ]; then report_none "$dst" "$src"; return; fi

  if ! mkdir -p "$(dirname "$dst")"; then
    report_fail "$dst" "$src" "ディレクトリを作成できない"
    return
  fi

  if [ "$mode" = mv ]; then
    if mv "$src" "$dst"; then
      report_ok "$src" "$dst" "$label"
    else
      report_fail "$dst" "$src" "mv に失敗"
    fi
    return
  fi

  tmp="$dst.tmp.$$"
  if cp "$src" "$tmp" \
    && [ "$(wc -c < "$tmp")" -eq "$(wc -c < "$src")" ] \
    && mv "$tmp" "$dst"; then
    report_ok "$src" "$dst" "$label"
  else
    rm -f "$tmp" 2>/dev/null || true
    report_fail "$dst" "$src" "コピーが不完全"
  fi
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
      if printf 'DEVELOPMENT_TEAM=%s\nAPI_SECRET=%s\n' "$dev_team" "$api_secret" > apps/shelf/ios/.env; then
        report_ok "$shelf_secrets + apps/todo/ios/.env" apps/shelf/ios/.env 生成
      else
        report_fail apps/shelf/ios/.env "$shelf_secrets" "書き込みに失敗"
      fi
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
echo "== 結果: 処理済み $done_count / スキップ $skipped / 未解決 $notfound / 失敗 $failed =="

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
check_rc=$?

if [ "$failed" -gt 0 ]; then
  echo
  echo "❌ 移行中に $failed 件失敗しました。上の「失敗」を確認してください。"
  exit 1
fi
exit "$check_rc"
