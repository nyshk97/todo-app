# 動作確認手順

## API

- テスト実行: `cd apps/api && npm test`

## iOS アプリ

- 実機にインストール: `mise run build:ios` → Xcode で iPhone を選択して Cmd+R

## macOS アプリ

- ビルド＆起動: `mise run build:mac`

## リリース

- ビルド: `mise run build`
- リリース作成: `mise run release -- <version>`
