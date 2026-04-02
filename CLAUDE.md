# 開発メモ

## プロジェクト構成

- `apps/api/` - Hono + Cloudflare Workers + D1 (SQLite)
- `apps/ios/` - SwiftUI iOS アプリ + WidgetKit
- `apps/macos/` - SwiftUI macOS メニューバーアプリ
- `packages/shared/` - 共有型定義 (TypeScript)
- `scripts/` - ビルド・リリース・プロジェクト生成スクリプト

## API

- 本番: `https://todo-app-api.d0ne1s-todo.workers.dev`
- 認証: `Authorization: Bearer done1s-todo-claudeflare-secret-desu`
- DB マイグレーション: `apps/api/migrations/` に SQL ファイルを追加し `npx wrangler d1 migrations apply todo-app-db --remote` で適用
- テストの DB スキーマ: `apps/api/src/__tests__/api.test.ts` 内に直書き。マイグレーション追加時はここも更新すること
- 日付は JST (UTC+9) で計算。`apps/api/src/date.ts` の `toJST()` ヘルパーを使用
- D1 の prepared statement で `null` をバインドしても値がクリアされない。`column = NULL` と raw SQL で書くこと

## iOS アプリ

- XcodeGen で `project.yml` からプロジェクト生成。`.xcodeproj` は gitignore 対象
- `apps/ios/.env` に `DEVELOPMENT_TEAM=<Team ID>` を設定（git 管理外）
- Personal Team 署名のため実機インストールは 7 日で期限切れ
- ウィジェットのバンドル ID: `com.d0ne1s.todoapp.widget`
- WidgetKit 更新: ViewModel 内で `WidgetCenter.shared.reloadAllTimelines()` を呼ぶ
- `LazyVStack` で同じ ID を複数の `ForEach` で使うとキャッシュバグが起きる。完了済みタスクには `.id("done-\(todo.id)")` で回避
- `contextMenu` は dimming バグがあるので使わない。タスク名タップで編集、ゴミ箱アイコンで即削除
- `onTapGesture` と `onDrag` は共存可能だが、`onLongPressGesture` と `onDrag` は競合する
- 実機インストール: `mise run build:ios` で Xcode を開き、iPhone を選択して Cmd+R。CLI の `xcodebuild` は署名の認証情報が不足するため Xcode GUI 経由が必要

## macOS アプリ

- メニューバー常駐 + フローティングパネル形式（`NSPanel`）
- `KeyablePanel` サブクラスで `canBecomeKey` を有効にしないとテキスト入力ができない
- `styleMask` に `.titled` や `.hudWindow` を含めるとダークなタイトルバーが出る。ボーダーレスにして角丸背景 + カスタム×ボタンで対応
- パネル表示時に `NotificationCenter` 経由でデータを再読み込み
- 署名なしでビルド: `CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO`
- `isMovableByWindowBackground = true` だと `onDrag` が奪われる。ヘッダーのみに `WindowDragView`（NSViewRepresentable）を配置して対応

## ビルド・リリース

- `bash scripts/generate-projects.sh` - iOS/macOS の Xcode プロジェクト生成（`.env` の Team ID をプレースホルダーに置換）
- `bash scripts/build.sh` - macOS アプリを Release ビルドして zip 化
- `bash scripts/release.sh <version>` - GitHub Release 作成。出力される SHA256 で homebrew-tap の Cask を更新
- homebrew-tap: `nyshk97/homebrew-tap` リポジトリの `Casks/todo-mac.rb` を version と sha256 で更新

## Brewfile

`~/Library/CloudStorage/Dropbox/Brewfile` に `cask 'nyshk97/tap/todo-mac'` を記載済み
