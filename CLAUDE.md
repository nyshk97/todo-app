# 開発メモ

## プロジェクト構成

- `apps/api/` - Hono + Cloudflare Workers + D1 (SQLite)
- `apps/web/` - React + Vite (SPA)、Cloudflare Pages にデプロイ
- `packages/shared/` - 共有型定義 (TypeScript)

## よく使うコマンド

`.mise.toml` にタスク定義あり。`mise tasks` で一覧表示。

## デプロイ・ビルド

- API: `mise run deploy`（Cloudflare Workers）
- Web: `mise run deploy:web`（Cloudflare Pages、Git連携なし・手動デプロイ）
- DB マイグレーション: `mise run deploy:migrate`（`apps/api/migrations/` に SQL 追加後に実行）
- iOS: `mise run build:ios`（xcodegen でプロジェクト生成 → Xcode で開く → Cmd+R で実機ビルド）

## API

- 本番: https://todo-shelf-api.d0ne1s-todo.workers.dev
- Web: https://todo-shelf-web.pages.dev
- 認証: `Authorization: Bearer <API_SECRET>`
- D1 の prepared statement で `null` をバインドしても値がクリアされない。`column = NULL` と raw SQL で書くこと
- 日付は JST (UTC+9) で計算

## シークレット・バインディング

### API（Cloudflare Workers）
- シークレット（`wrangler secret put` で管理）:
  - `API_SECRET` - API 認証トークン
  - `TODO_APP_API_SECRET` - todo-app API 連携用トークン
- バインディング:
  - D1: `DB` → `todo-shelf-db`
  - R2: `ATTACHMENTS` → `todo-shelf-attachments`
- vars（wrangler.toml で管理）:
  - `TODO_APP_API_URL`

### Web（Cloudflare Pages）
- `apps/web/.env` にローカル用の環境変数あり（`VITE_API_URL`, `VITE_API_SECRET` 等）
- 本番の環境変数は Cloudflare Pages ダッシュボードで設定

### iOS
- xcodegen で `apps/ios/project.yml` からプロジェクト生成
- API URL・シークレットは `apps/ios/Sources/Secrets.swift` と `APIClient.swift` にハードコード
- `DEVELOPMENT_TEAM` は project.yml でプレースホルダー（Xcode で初回ビルド時に自動設定される）

## コンセプト

- Todoist 代替。「今すぐやらないけど忘れたくないこと」を管理する場所
- 既存 todo-app（今日やるタスク管理）の補完アプリ
- タスクに「完了」の概念はない。アクションは「移動」か「削除」
- 既存 todo-app へのタスク移動機能あり（API 経由で POST → Shelf から削除）
