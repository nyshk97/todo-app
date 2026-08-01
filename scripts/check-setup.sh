#!/bin/bash
# 新しい環境で clone したあと、git 管理外の設定ファイルが揃っているか確認する。
# 何も書き換えないので何度実行してもよい。
#
#   bash scripts/check-setup.sh
#
# 「ファイルがある」だけでなく必須キーが埋まっているかまで見る。
# ファイルの有無しか見ないと、雛形をコピーしただけの状態や中身が壊れた状態を
# 「揃っている」と誤報告して、後の切り分けの出発点が嘘になるため。
# 秘密の値そのものは表示せず、キー名と状態だけを報告する。

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

missing=0

# check <パス> <説明> <復旧方法> [必須キー...]
check() {
  local path="$1" desc="$2" howto="$3"
  shift 3

  if [ ! -s "$path" ]; then
    printf '  \033[31mNG\033[0m   %-42s %s\n' "$path" "$desc"
    printf '       → %s\n' "$howto"
    missing=$((missing + 1))
    return
  fi

  local bad="" key value
  for key in "$@"; do
    value="$(sed -n "s/^${key}=//p" "$path" | head -1)"
    if [ -z "$value" ]; then
      bad="$bad ${key}(未設定)"
    elif [[ "$value" == *REPLACE_ME* ]]; then
      bad="$bad ${key}(雛形のまま)"
    fi
  done

  if [ -n "$bad" ]; then
    printf '  \033[31mNG\033[0m   %-42s %s\n' "$path" "$desc"
    printf '       中身が不十分:%s\n' "$bad"
    printf '       → %s\n' "$howto"
    missing=$((missing + 1))
  else
    printf '  \033[32mOK\033[0m   %-42s %s\n' "$path" "$desc"
  fi
}

echo "== git 管理外の設定ファイル =="
echo
echo "todo"
check apps/todo/api/.dev.vars "API ローカル開発用のシークレット" \
  "既存環境からコピー（wrangler dev でのみ使用）" \
  API_SECRET
check apps/todo/ios/.env "DEVELOPMENT_TEAM / API_SECRET" \
  "既存環境からコピー、または手で作成" \
  DEVELOPMENT_TEAM API_SECRET
check apps/todo/macos/.env "DEVELOPMENT_TEAM / API_SECRET" \
  "既存環境からコピー、または手で作成" \
  DEVELOPMENT_TEAM API_SECRET

echo
echo "shelf"
check apps/shelf/api/.dev.vars "API ローカル開発用のシークレット" \
  "既存環境からコピー" \
  API_SECRET TODO_APP_API_SECRET
check apps/shelf/ios/.env "DEVELOPMENT_TEAM / API_SECRET" \
  "既存環境からコピー、または手で作成" \
  DEVELOPMENT_TEAM API_SECRET
check apps/shelf/web/.env "ローカル開発用の VITE_* 変数" \
  "cp apps/shelf/web/.env.example apps/shelf/web/.env して値を埋める" \
  VITE_API_URL VITE_API_SECRET VITE_TODO_APP_API_URL
check apps/shelf/web/.env.production "本番デプロイ用の VITE_* 変数" \
  "cp apps/shelf/web/.env.example apps/shelf/web/.env.production して VITE_API_SECRET を実値にする" \
  VITE_API_URL VITE_API_SECRET VITE_TODO_APP_API_URL

echo
echo "== 補足 =="
echo "  Secrets.swift（iOS 3つ）は .env があれば scripts/generate-projects.sh が生成するのでコピー不要"
echo "  node_modules は npm ci で用意する"
echo "  .env.production の値が本番として妥当か（localhost を向いていないか）は"
echo "  apps/shelf/web/vite.config.ts の production ビルド時ガードが別途検証する"

echo
if [ "$missing" -eq 0 ]; then
  echo "✅ 設定ファイルは揃っています。次: npm ci && mise run generate"
  exit 0
else
  echo "❌ $missing 件不足しています。上の「→」の手順で用意してください。"
  exit 1
fi
