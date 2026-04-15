# コメント添付ファイル & アーカイブ機能

## 概要・やりたいこと

1. **コメントにファイルを添付できるようにする** — 画像やPDF等をコメントに添付し、画像はプレビュー表示、それ以外はファイル名+ダウンロードリンクで表示
2. **「今日のTODOへ移動」時にコメント・添付ファイルを保持する** — 現状は物理削除でコメントが消えるため、論理削除（archived）に変更しデータを保持。Archiveタブから閲覧・復元可能にする

## 前提・わかっていること

### 決定事項（/dig で合意済み）

| 項目 | 決定 |
|---|---|
| ストレージ | Cloudflare R2 |
| 添付の紐づけ | コメントに紐づける |
| ファイル種別 | 画像 + 一般ファイル（画像はプレビュー、それ以外はDLリンク） |
| 添付上限 | 1コメント5ファイル、1ファイル10MB |
| move-to-today | 論理削除（archived）に変更、データ保持 |
| Archive閲覧 | 専用タブ、フラットリスト（移動日順） |
| 復元機能 | あり（Shelfに戻す） |
| R2アクセス | Workers経由プロキシ（認証付き） |
| アップロード | マルチパートフォームデータ（既存JSON→マルチパートに一括変更） |
| DB設計 | `attachments` 別テーブル（CASCADE削除） |
| 対象 | Web + API + iOS 一括実装 |

### 現状の構成

- API: Hono + Cloudflare Workers + D1（マイグレーション: `apps/api/migrations/`）
- Web: React + Vite SPA
- iOS: SwiftUI + MVVM（`apps/ios/`）
- 共有型: `packages/shared/src/types.ts`
- 認証: `Authorization: Bearer <API_SECRET>`
- R2: 未設定（今回新規追加）

### 現状のコメントAPI

- `POST /tasks/:id/comments` — JSON `{ content: string }` → マルチパートに変更
- `GET /tasks/:id/comments` — コメント一覧（attachmentsも含めて返す必要あり）
- `PATCH /comments/:id` — テキスト更新（添付の追加/削除は別エンドポイント）
- `DELETE /comments/:id` — コメント削除（CASCADE で attachments も削除、R2からも削除必要）

### 現状のmove-to-today

- `POST /tasks/:id/move-to-today` — 外部 todo-app API にタイトル+日付をPOST → Shelfタスクを物理DELETE
- `ON DELETE CASCADE` でコメントも自動削除される → これを論理削除に変更

### DBスキーマ変更が必要

- `tasks` テーブル: `archived_at TEXT` カラム追加（NULLなら通常タスク、値ありならアーカイブ済み）
- `attachments` テーブル: 新規作成

## 実装計画

### 事前準備 [人間👨‍💻]
- [ ] Cloudflare R2バケットを作成（`wrangler r2 bucket create todo-shelf-attachments`）

### Phase 1: DB・型定義の拡張 [AI🤖]
- [x] マイグレーション `0002_attachments_and_archive.sql` 作成
  - `attachments` テーブル: `id`, `comment_id` (FK CASCADE), `filename`, `content_type`, `size` (INTEGER), `r2_key`, `created_at`
  - `tasks` テーブル: `archived_at TEXT` カラム追加（デフォルトNULL）
  - インデックス: `idx_attachments_comment_id`, `idx_tasks_archived_at`
- [x] `packages/shared/src/types.ts` に型追加
  - `Attachment` インターフェース
  - `Comment` に `attachments: Attachment[]` 追加
  - `Task` に `archived_at: string | null` 追加
- [x] `apps/api/src/lib/db.ts` の `Bindings` に `ATTACHMENTS: R2Bucket` 追加
- [x] `apps/api/wrangler.toml` に R2バケットバインディング追加

### Phase 2: 添付ファイルAPI [AI🤖]
- [x] `apps/api/src/routes/attachments.ts` 新規作成
  - `GET /attachments/:id` — R2からファイル取得してプロキシ（認証付き、Content-Type設定）
  - `DELETE /attachments/:id` — D1レコード + R2オブジェクト削除
- [x] `apps/api/src/routes/comments.ts` 変更
  - `POST /tasks/:id/comments` をマルチパート対応に変更（content + files[]）
  - ファイルバリデーション: 最大5ファイル、1ファイル10MB
  - R2アップロード: キーは `{task_id}/{comment_id}/{uuid}_{filename}`
  - `attachments` テーブルへのレコード挿入
  - `GET /tasks/:id/comments` にattachmentsをJOINして返す
- [x] コメント削除時にR2オブジェクトも削除（DELETE /comments/:id 拡張）
- [x] `apps/api/src/index.ts` にattachmentsルート追加

### Phase 3: アーカイブAPI [AI🤖]
- [x] `apps/api/src/routes/tasks.ts` 変更
  - `POST /tasks/:id/move-to-today` — 物理削除 → `archived_at = nowJST()` に変更
  - `GET /projects/:id/tasks` — `WHERE archived_at IS NULL` 条件追加（通常タスクのみ）
  - `GET /tasks/upcoming` — `WHERE archived_at IS NULL` 条件追加
  - `GET /tasks/archived` — アーカイブ済みタスク一覧（archived_at DESC順、コメント数・元プロジェクト名付き）
  - `POST /tasks/:id/restore` — archived_at をNULLに戻して元のプロジェクト・セクションに復元
  - `DELETE /tasks/:id` — アーカイブタスクの完全削除時にR2のファイルも削除

### Phase 4: Web版 — 添付ファイルUI [AI🤖]
- [x] `apps/web/src/components/TaskDetail.tsx` 変更
  - コメント投稿フォームにファイル添付UI追加（ファイル選択ボタン + プレビュー）
  - `FormData` でマルチパート送信に変更
  - コメント表示に添付ファイル表示追加（画像はインラインプレビュー、その他はDLリンク）
  - 添付ファイル個別削除ボタン
- [x] `apps/web/src/lib/api.ts` にマルチパート送信用メソッド追加

### Phase 5: Web版 — アーカイブUI [AI🤖]
- [x] `apps/web/src/components/ArchiveView.tsx` 新規作成
  - アーカイブ済みタスクのフラットリスト（移動日順）
  - 元プロジェクト名表示
  - タスクタップでコメント・添付ファイル閲覧（TaskDetailの読み取り専用モードまたは共有）
  - 「Shelfに戻す」ボタン
- [x] `apps/web/src/components/App.tsx` にArchiveタブ/ルート追加

### Phase 6: iOS版 — 添付ファイル対応 [AI🤖]
- [x] `Sources/Models/` に `Attachment` モデル追加、`ShelfComment` に `attachments` プロパティ追加
- [x] `Sources/API/APIClient.swift` 変更
  - コメント投稿をマルチパートフォームデータに変更
  - 添付ファイルダウンロード/プレビュー用メソッド追加
  - 添付ファイル個別削除メソッド追加
- [x] `Sources/Views/TaskDetailSheet.swift` 変更
  - コメント投稿フォームにファイル添付UI（PhotosPicker + ファイルピッカー）
  - コメント表示に添付ファイル表示（画像はAsyncImageプレビュー、その他はリンク）
- [x] `Sources/ViewModels/ShelfViewModel.swift` に添付関連メソッド追加

### Phase 7: iOS版 — アーカイブ対応 [AI🤖]
- [x] `Sources/Views/ArchiveView.swift` 新規作成
  - アーカイブ済みタスクのリスト（移動日順）
  - 元プロジェクト名表示
  - タップでコメント・添付閲覧
  - 「Shelfに戻す」ボタン
- [x] `Sources/Views/ContentView.swift` にArchiveタブ追加（アイコン: archivebox）
- [x] `Sources/ViewModels/ShelfViewModel.swift` にアーカイブ関連メソッド追加（取得・復元）
- [x] `Sources/API/APIClient.swift` にアーカイブ関連APIメソッド追加

### Phase 8: 仕上げ [AI🤖]
- [x] タスク削除時のR2クリーンアップ確認（CASCADE削除 → R2ファイルは手動削除必要）
- [x] XcodeGen でプロジェクト再生成、ビルド確認
- [x] Web版ビルド確認

### デプロイ [人間👨‍💻]
- [ ] D1マイグレーション適用（`npx wrangler d1 migrations apply todo-shelf-db --remote`）
- [ ] wrangler.toml のR2バインディング確認
- [ ] Workers デプロイ（`npx wrangler deploy`）
- [ ] Web版デプロイ
- [ ] iOS実機ビルド・インストール

### 動作確認 [人間👨‍💻]
- [ ] コメントにテキスト+画像を添付して投稿 → プレビュー表示確認
- [ ] コメントにPDF等を添付 → ダウンロードリンク表示確認
- [ ] 添付ファイルの個別削除
- [ ] 「今日のTODOへ移動」→ Archiveタブでタスク・コメント・添付が閲覧可能
- [ ] Archiveから「Shelfに戻す」→ 元プロジェクトに復元される
- [ ] iOS版で同等の操作確認

## ログ
### 試したこと・わかったこと
- `attachmentURL` メソッドを `nonisolated` にする必要あり（actor APIClient から同期的に呼び出すため）
- 認証ミドルウェアに `?token=` クエリパラメータ対応を追加（`<img src>` や `<a href>` での直接アクセス用）
- iOS版の `moveTaskToToday` はiOS→todo-app API直接POST + iOS→Shelf API move-to-today の2段構成（Workers間fetch制約の回避策を踏襲）

### 方針変更
（実装中に随時追記）
