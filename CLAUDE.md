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

## 通信遅延の調査手順

「時々 API 通信が数秒かかる」報告あり（2026-07 時点で原因未特定。正常時は Shelf API・todo-app API とも 40〜180ms）。計測ログ仕込み済み:

- **クライアント側の記録**: 1秒超 or 失敗したリクエストを localStorage `slow-requests`（直近50件）と console `[slow-request]` に記録している（`apps/web/src/lib/api.ts`。todo-app への移動 POST も App.tsx で記録対象）。devtools console で `JSON.parse(localStorage.getItem("slow-requests"))` で確認
- **サーバー側の記録**: 全リクエストの所要時間を `{"method","path","status","ms"}` の JSON で console.log している（`apps/api/src/index.ts` のミドルウェア）。Workers Logs 有効化済み（wrangler.toml の `[observability]`）なので Cloudflare ダッシュボード → Workers & Pages → todo-shelf-api → Logs で過去分（無料プランで3日保持）を検索できる。リアルタイム監視は `npx wrangler tail todo-shelf-api`
- **切り分け**: localStorage に記録あり＋サーバーログの ms が小さい → ネットワーク経路。両方大きい → サーバー側（D1 レイテンシスパイク等）。localStorage に記録がないのに遅く感じた → フロント実装起因（下記）
- **フロントの既知の「遅く見える」要因**（未修正）:
  - 「今日へ移動」は todo-app POST → Shelf POST を直列 await し、完了までモーダルが開いたまま。エラーハンドリングもないため失敗するとモーダルが閉じず固まって見える（`App.tsx` handleMoveToToday）
  - refreshKey 変更のたびに ProjectView が key ごと再マウントされ「読み込み中...」からフル再取得になる（`App.tsx`）
  - 詳細モーダルからの削除が DELETE 送信前に refreshKey を上げて再取得とレースする問題は 175cb45 で修正済み（DELETE 成功後に再取得）

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

## プロジェクト名のハードコード

- コード内で `p.name === "Shelf"`, `"Backlog"`, `"Archive"` などプロジェクト名の完全一致で表示制御している箇所がある（Web: App.tsx, Fab.tsx / iOS: ContentView.swift）
- プロジェクト名を変更する場合、コード変更 → デプロイ → DB リネームの順で行うか、同時に反映すること

## dnd-kit

- 複数コンテナ間 D&D では `closestCenter` ではなくカスタム collision detection を使い、タスク要素を droppable ゾーンより優先する
- 同一コンテナ内の並べ替えは `arrayMove` を使う（手動 splice はドラッグ方向でズレる）

## iOS

- SwiftUI 標準の `.onDrag`/`.onDrop` はセクション間 D&D に不向き（アニメーション制御の限界、スクロールとの競合）。カスタム D&D は `LongPressGesture.sequenced(before: DragGesture)` + `PreferenceKey` で frame 収集 + `UIScrollView` introspection でオートスクロール、という構成で実装している（`DragController.swift` 参照）
- カスタムジェスチャーを付ける View は `Button` を避けて `HStack + .onTapGesture` にする。`Button` + 外側 gesture は `.simultaneousGesture`（両発火）/ `.gesture`（Button 常勝）/ `.highPriorityGesture`（外側常勝）のどれも破綻する
- ジェスチャーに紐づく一時状態は `@GestureState` を使うとキャンセル時も自動リセットされる。手動管理の `@State` フラグは `.onEnded` が呼ばれない経路で汚染されるリスクあり
- 新規 Swift ファイルを追加したら `xcodegen generate` を再実行してからビルドする（自動では Xcode プロジェクトに含まれない）
- `xcodegen generate` 直後はハーネス側 SourceKit のキャッシュが古いまま「Cannot find type 'XX'」「Cannot find 'Theme' in scope」等を大量に出すことがあるが、実際の `xcodebuild` は通る。診断ノイズに振り回されて書き換えに走らず、`mise run build:ios` か `xcodebuild` で実ビルドを確認する
- プロジェクト内の `struct Task: Codable`（Models.swift）が Swift 標準の並行処理 `Task` を shadow する。非同期ブロックを起動する時は `Swift.Task { ... }` と修飾すること（素の `Task { ... }` は `Task(from: Decoder)` に解決されて "trailing closure passed to parameter of type 'any Decoder'" エラーになる）

## コンセプト

- Todoist 代替。「今すぐやらないけど忘れたくないこと」を管理する場所
- 既存 todo-app（今日やるタスク管理）の補完アプリ
- タスクに「完了」の概念はない。アクションは「移動」か「削除」
- 既存 todo-app へのタスク移動機能あり（API 経由で POST → Shelf から削除）
