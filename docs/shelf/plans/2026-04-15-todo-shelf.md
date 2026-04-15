# todo-shelf 構築

## 概要・やりたいこと

「今すぐやらないけど忘れたくないこと」を管理するアプリ **Shelf** を新規構築する。
現在 Todoist で管理している「TODO」「アイデア」「いつか」の3プロジェクトを、自作アプリに移行する。

既存の自作 todo-app（今日やるタスク管理）の補完アプリとして位置づけ、Shelf のタスクを既存 todo-app に移動する連携機能も持つ。

## 前提・わかっていること

### 機能要件
- **プロジェクト**: CRUD対応（初期は TODO / アイデア / いつか の3つ）
- **セクション**: プロジェクト内のグルーピング。CRUD + 並べ替え
- **タスク**: 追加・削除（確認ダイアログ付き）。**完了の概念なし**（移動 or 削除）
- **セクション未所属タスク**: プロジェクト直下にも配置可
- **タスク追加**: セクション内の「＋」から追加
- **タスク移動**: プロジェクト間・セクション間の移動
- **既存todo-appへの移動**: 移動先として選べる。APIにPOSTして作成、Shelfからは削除
- **ドラッグ&ドロップ**: タスク・セクションの並べ替え
- **期日設定**: 特定日付のみ（繰り返しなし）
- **期日バッジ**: 3日前→オレンジ、当日以降→赤。位置は元のセクション内に留まる
- **期日通知バッジ**: タブ横に「期限近い: N」表示
- **コメント**: プレーンテキスト + URL自動リンク化
- **サブタスク**: 初期リリースではスキップ
- **ファイル添付**: 初期リリースではスキップ
- **PWA**: 不要。モバイルは Safari で開く

### UI
- タブ型ナビゲーション（サイドバーなし）
- プロジェクトをタブで切り替え
- タブ横に期日通知バッジ

### 技術スタック
| コンポーネント | 技術 | デプロイ先 |
|---|---|---|
| API | Hono + TypeScript | Cloudflare Workers |
| DB | D1 (SQLite) | Cloudflare D1 |
| Web | React + Vite (SPA) | Cloudflare Pages |
| iOS | SwiftUI | 後日 |
| 認証 | Bearerトークン固定値 | — |

### リポジトリ
- 別リポ `todo-shelf`（GitHub: nyshk97/todo-shelf）
- モノレポ構成（`apps/api`, `apps/web`, `packages/shared`）
- 現在の `todo-app-future` ディレクトリをリネーム

### 開発順序
API → Web → iOS（iOS は後日別計画）

### 既存 todo-app の情報
- API: `https://todo-app-api.d0ne1s-todo.workers.dev`
- 認証: Bearer トークン
- タスク作成: `POST /todos` (body: `{ title, date }`)
- Hono + Cloudflare Workers + D1 構成

## 実装計画

### 事前準備 [人間👨‍💻]
- [x] ディレクトリリネーム: `mv ~/todo-app-future ~/todo-shelf`
- [x] GitHub に `todo-shelf` リポジトリを作成
- [x] Cloudflare ダッシュボードで D1 データベース `todo-shelf-db` を作成 (database_id: 96200c31-66e0-48fe-94a5-b2f9a40523b9)
- [x] Cloudflare Workers の API_SECRET を設定（`wrangler secret put API_SECRET`）— Phase 3 デプロイ後に実施

### Phase 1: プロジェクト基盤 [AI🤖]
- [x] モノレポ初期構成（`apps/api`, `apps/web`, `packages/shared`, `package.json` workspaces）
- [x] 共有型定義（`packages/shared`）: Project, Section, Task, Comment の型
- [x] mise タスク定義（`.mise.toml`）
- [x] CLAUDE.md 作成

### Phase 2: API — データモデル & マイグレーション [AI🤖]
- [x] D1 マイグレーション作成
  - `projects` テーブル（id, name, position, created_at, updated_at）
  - `sections` テーブル（id, project_id, name, position, created_at, updated_at）
  - `tasks` テーブル（id, project_id, section_id nullable, title, due_date nullable, position, created_at, updated_at）
  - `comments` テーブル（id, task_id, content, created_at, updated_at）
- [x] wrangler.toml 設定

### Phase 3: API — エンドポイント実装 [AI🤖]
- [x] 認証ミドルウェア（Bearer トークン）
- [x] プロジェクト CRUD: `GET /projects`, `POST /projects`, `PATCH /projects/:id`, `DELETE /projects/:id`
- [x] セクション CRUD: `GET /projects/:id/sections`, `POST /projects/:id/sections`, `PATCH /sections/:id`, `DELETE /sections/:id`
- [x] セクション並べ替え: `PATCH /projects/:id/sections/reorder`
- [x] タスク CRUD: `GET /projects/:id/tasks`, `POST /tasks`, `PATCH /tasks/:id`, `DELETE /tasks/:id`
- [x] タスク並べ替え・移動: `PATCH /tasks/:id`（project_id, section_id, position を更新）
- [x] タスク一括並べ替え: `PATCH /tasks/reorder`
- [x] コメント CRUD: `GET /tasks/:id/comments`, `POST /tasks/:id/comments`, `PATCH /comments/:id`, `DELETE /comments/:id`
- [x] 期日近接タスク取得: `GET /tasks/upcoming?days=3`
- [x] 既存todo-appへの移動: `POST /tasks/:id/move-to-today`（既存APIにPOST → Shelfから削除）
- [x] API テスト（Vitest + Miniflare）

### Phase 3後の準備 [人間👨‍💻]
- [x] API をデプロイ: `wrangler deploy`
- [x] D1 マイグレーション適用: `wrangler d1 migrations apply todo-shelf-db --remote`

### Phase 4: Web — 基盤 & プロジェクトビュー [AI🤖]
- [x] Vite + React + TypeScript プロジェクト初期構成
- [x] DESIGN.md 導入（`npx getdesign@latest add linear`）— Linear 風デザインシステム
- [x] API クライアント（fetch ラッパー + Bearer トークン）
- [x] ルーティング（React Router）: `/` → デフォルトプロジェクト表示
- [x] タブ型ナビゲーション（プロジェクト切り替え + 期日通知バッジ）
- [x] プロジェクトビュー: セクション一覧 + セクション未所属タスク表示
- [x] タスク追加（セクション内の「＋」ボタン + インライン入力）
- [x] タスク削除（確認ダイアログ付き）

### Phase 5: Web — タスク詳細 & インタラクション [AI🤖]
- [x] タスク詳細パネル（クリックで開く）: タイトル編集、期日設定、コメント一覧
- [x] 期日ピッカー（日付選択 UI）
- [x] 期日バッジ表示（3日前→オレンジ、当日以降→赤）
- [x] コメント追加・編集・削除
- [x] コメント内 URL の自動リンク化
- [x] タスク移動（プロジェクト間・セクション間）— 移動先選択 UI
- [x] 既存todo-appへの移動ボタン

### Phase 6: Web — ドラッグ&ドロップ & セクション管理 [AI🤖]
- [ ] タスクのドラッグ&ドロップ並べ替え（セクション内）
- [ ] セクション CRUD UI（追加・リネーム・削除）
- [ ] セクションのドラッグ&ドロップ並べ替え
- [ ] プロジェクト管理 UI（追加・リネーム・削除）

### Phase 6後の準備 [人間👨‍💻]
- [ ] Web をデプロイ: Cloudflare Pages に接続
- [ ] 環境変数設定（API URL, API_SECRET）

### Phase 7: Todoist データ移行 [AI🤖]
- [ ] Todoist API からデータエクスポートスクリプト作成（プロジェクト・セクション・タスク・コメント）
- [ ] Shelf API への一括インポートスクリプト作成
- [ ] 移行テスト（ローカル環境で実行・確認）

### 本番データ移行 [人間👨‍💻]
- [ ] Todoist API トークンを取得
- [ ] 移行スクリプト実行（本番 Shelf API に対して）
- [ ] データ確認後、Todoist を卒業 🎉

## ログ
### 試したこと・わかったこと
（実装中に随時追記）

### 方針変更
（実装中に随時追記）
