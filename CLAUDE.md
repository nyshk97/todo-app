# 開発メモ

## プロジェクト構成

- `apps/api/` - Hono + Cloudflare Workers + D1 (SQLite)
- `apps/web/` - React + Vite (SPA)、Cloudflare Pages にデプロイ
- `packages/shared/` - 共有型定義 (TypeScript)

## API

- 本番: (未デプロイ)
- 認証: `Authorization: Bearer <API_SECRET>`（値は `.env` で管理）
- DB マイグレーション: `apps/api/migrations/` に SQL ファイルを追加し `npx wrangler d1 migrations apply todo-shelf-db --remote` で適用
- D1 の prepared statement で `null` をバインドしても値がクリアされない。`column = NULL` と raw SQL で書くこと
- 日付は JST (UTC+9) で計算

## コンセプト

- Todoist 代替。「今すぐやらないけど忘れたくないこと」を管理する場所
- 既存 todo-app（今日やるタスク管理）の補完アプリ
- タスクに「完了」の概念はない。アクションは「移動」か「削除」
- 既存 todo-app へのタスク移動機能あり（API 経由で POST → Shelf から削除）
