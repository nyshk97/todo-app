#!/bin/bash
# 新しい環境で clone したあと、git 管理外の設定ファイルが揃っているか確認する。
# 何も書き換えないので何度実行してもよい。
#
#   bash scripts/check-setup.sh
#
# 秘密の値そのものは表示せず、有無だけを報告する。

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

missing=0

# check <パス> <説明> <復旧方法>
check() {
  local path="$1" desc="$2" howto="$3"
  if [ -s "$path" ]; then
    printf '  \033[32mOK\033[0m   %-42s %s\n' "$path" "$desc"
  else
    printf '  \033[31mNG\033[0m   %-42s %s\n' "$path" "$desc"
    printf '       → %s\n' "$howto"
    missing=$((missing + 1))
  fi
}

echo "== git 管理外の設定ファイル =="
echo
echo "todo"
check apps/todo/api/.dev.vars "API ローカル開発用のシークレット" \
  "既存環境からコピー（wrangler dev でのみ使用）"
check apps/todo/ios/.env "DEVELOPMENT_TEAM / API_SECRET" \
  "既存環境からコピー、または手で作成"
check apps/todo/macos/.env "DEVELOPMENT_TEAM / API_SECRET" \
  "既存環境からコピー、または手で作成"

echo
echo "shelf"
check apps/shelf/api/.dev.vars "API ローカル開発用のシークレット" \
  "既存環境からコピー"
check apps/shelf/ios/.env "DEVELOPMENT_TEAM / API_SECRET" \
  "既存環境からコピー、または手で作成"
check apps/shelf/web/.env "ローカル開発用の VITE_* 変数" \
  "cp apps/shelf/web/.env.example apps/shelf/web/.env して値を埋める"
check apps/shelf/web/.env.production "本番デプロイ用の VITE_* 変数" \
  "cp apps/shelf/web/.env.example apps/shelf/web/.env.production して VITE_API_SECRET を実値にする"

echo
echo "== 補足 =="
echo "  Secrets.swift（iOS 3つ）は .env があれば scripts/generate-projects.sh が生成するのでコピー不要"
echo "  node_modules は npm ci で用意する"

echo
if [ "$missing" -eq 0 ]; then
  echo "✅ 設定ファイルは揃っています。次: npm ci && mise run generate"
  exit 0
else
  echo "❌ $missing 件不足しています。上の「→」の手順で用意してください。"
  exit 1
fi
