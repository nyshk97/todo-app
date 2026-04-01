#!/bin/bash
# .env から DEVELOPMENT_TEAM を読み込み、xcodegen generate を実行するスクリプト
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

for app in ios macos; do
  APP_DIR="$REPO_ROOT/apps/$app"
  ENV_FILE="$APP_DIR/.env"

  if [ ! -f "$ENV_FILE" ]; then
    echo "Warning: $ENV_FILE not found. Using empty DEVELOPMENT_TEAM."
    DEVELOPMENT_TEAM=""
  else
    source "$ENV_FILE"
  fi

  # project.yml のプレースホルダーを置換して一時ファイルを作成
  sed "s/DEVELOPMENT_TEAM_PLACEHOLDER/$DEVELOPMENT_TEAM/g" "$APP_DIR/project.yml" > "$APP_DIR/project.yml.tmp"
  mv "$APP_DIR/project.yml.tmp" "$APP_DIR/project.yml.resolved"

  # xcodegen 実行
  cd "$APP_DIR"
  xcodegen generate --spec project.yml.resolved
  rm project.yml.resolved

  echo "✅ $app project generated"
done
