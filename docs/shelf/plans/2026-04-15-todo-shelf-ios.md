# todo-shelf iOS アプリ

## 概要・やりたいこと

todo-shelf（Todoist代替の「今すぐやらないけど忘れたくないこと」管理アプリ）のiOSネイティブアプリを構築する。
Web版とほぼ同等の機能をSwiftUIで実装し、既存APIをそのまま利用する。

## 前提・わかっていること

### 技術構成
- SwiftUI一本、iOS 18.0+ターゲット
- MVVM: `@Observable` ViewModel + `actor` APIClient（既存todo-app踏襲）
- XcodeGen（`project.yml`）で管理、`.xcodeproj` はgit外
- SPM、外部ライブラリなし
- 認証: `Secrets.swift`（`.gitignore`）にBearerトークンをハードコード
- 配置: モノレポ `apps/ios/` 内
- 個人利用のみ（Xcode直接インストール）

### 画面構成
- 下部タブバーでプロジェクト切り替え（動的、期日バッジ付き）
- タスク詳細: ボトムシート（`.sheet`）
- セクション/プロジェクト管理: `.contextMenu`（長押し）
- タスク追加: セクション末尾のインライン入力
- ドラッグ&ドロップ: `onDrag`/`onDrop` + `DropDelegate`（既存todo-app踏襲）

### 機能範囲（Web版ほぼ全機能）
- プロジェクト CRUD
- セクション CRUD + 並べ替え
- タスク CRUD + 並べ替え + プロジェクト間/セクション間移動
- 期日設定 + 期日バッジ（3日前→オレンジ、当日以降→赤）
- コメント CRUD + URL自動リンク化
- 「今日のTODOへ移動」機能
- Pull-to-refresh
- プッシュ通知なし、ウィジェットなし

### データ管理
- 起動時に全プロジェクトデータ一括取得、メモリ保持
- オフライン非対応（エラー時アラート表示）

### デザイン
- Web版のダークテーマベース（濃いダーク背景 + グレー系カード）

### 既存コードの参考元
- 既存todo-app iOS: `/Users/d0ne1s/todo-app/apps/ios`
  - `APIClient.swift`: actor ベースのシングルトン、URLSession + Bearer認証
  - `ContentView.swift`: `onDrag`/`onDrop` + `TodoDropDelegate` でドラッグ&ドロップ
  - `Theme.swift`: 時間帯ベースのLight/Night切り替え（Shelfでは不使用、Web版ダークテーマベースにする）
  - `project.yml`: XcodeGen設定

### API情報
- 本番: `https://todo-shelf-api.d0ne1s-todo.workers.dev`
- 認証: `Authorization: Bearer <API_SECRET>`
- エンドポイント:
  - `GET /projects` / `POST /projects` / `PATCH /projects/:id` / `DELETE /projects/:id`
  - `GET /projects/:id/sections` / `POST /projects/:id/sections` / `PATCH /sections/:id` / `DELETE /sections/:id` / `PATCH /projects/:id/sections/reorder`
  - `GET /projects/:id/tasks` / `POST /tasks` / `PATCH /tasks/:id` / `DELETE /tasks/:id` / `PATCH /tasks/reorder`
  - `GET /tasks/upcoming?days=3`
  - `POST /tasks/:id/move-to-today`
  - `GET /tasks/:id/comments` / `POST /tasks/:id/comments` / `PATCH /comments/:id` / `DELETE /comments/:id`

## 実装計画

### 事前準備 [人間👨‍💻]
- [x] XcodeGen がインストール済みか確認（`xcodegen version`）

### Phase 1: プロジェクト基盤 [AI🤖]
- [x] `apps/ios/` ディレクトリ作成
- [x] `project.yml` 作成（XcodeGen設定、iOS 18.0+、SwiftUI App lifecycle）
- [x] `Sources/ShelfApp.swift` — エントリーポイント
- [x] `Sources/Secrets.swift` — APIシークレット定義 + `.gitignore` 追加
- [x] `Sources/Models/` — Swift型定義（Project, Section, Task, Comment, UpcomingTask）
- [x] `Sources/API/APIClient.swift` — actor ベースのAPIクライアント（全エンドポイント対応）
- [x] XcodeGen でプロジェクト生成、ビルド確認

### Phase 2: データ層とViewModel [AI🤖]
- [x] `Sources/ViewModels/ShelfViewModel.swift` — `@Observable` メインViewModel
  - 全プロジェクトデータの一括取得・メモリ保持
  - プロジェクト/セクション/タスク/コメントの CRUD 操作
  - 期日近接タスク数の算出（バッジ用）
  - エラーハンドリング（アラート表示用）
  - Pull-to-refresh

### Phase 3: メイン画面 — タブバーとプロジェクトビュー [AI🤖]
- [x] `Sources/Views/ContentView.swift` — 下部タブバー（プロジェクト切り替え + 期日バッジ）
- [x] `Sources/Views/ProjectView.swift` — セクション一覧 + セクション未所属タスク表示
- [x] `Sources/Views/SectionView.swift` — セクション内タスク一覧
- [x] `Sources/Views/TaskRow.swift` — タスク行（タイトル、期日バッジ、コメント件数バッジ）
- [x] `Sources/Theme.swift` — Web版ダークテーマベースのカラー定義
- [x] Pull-to-refresh 実装

### Phase 4: タスク操作 [AI🤖]
- [x] インラインタスク追加（セクション末尾の「+ タスクを追加」）
- [x] タスク削除（長押しメニュー、確認ダイアログ付き）
- [x] ドラッグ&ドロップ並べ替え（`onDrag`/`onDrop` + `DropDelegate`）
- [x] タスク移動（プロジェクト間・セクション間）— MoveTaskSheet

### Phase 5: タスク詳細パネル [AI🤖]
- [x] `Sources/Views/TaskDetailSheet.swift` — ボトムシート
  - タイトル編集
  - 期日設定（DatePicker）
  - プロジェクト/セクション移動
  - 「今日のTODOへ移動」ボタン
- [x] コメント一覧・追加・編集・削除（TaskDetailSheet内にCommentRow組み込み）
- [x] `Sources/Views/LinkedText.swift` — URL自動リンク化（既存todo-app参考）

### Phase 6: セクション・プロジェクト管理 [AI🤖]
- [x] セクション追加（一覧下部の「+ セクション」ボタン）
- [x] セクション名変更・削除（`.contextMenu` 長押し）
- ~~セクション並べ替え（ドラッグ&ドロップ）~~ — セクション間の D&D は API の reorder で対応済み、UI は後日
- [x] プロジェクト追加（ツールバーメニューの「+」）
- [x] プロジェクト名変更・削除（ツールバーメニュー）

### Phase 7: 仕上げ [AI🤖]
- [x] エラーハンドリング統一（ネットワークエラー時のアラート表示）
- [x] 仮アプリアイコン設定（空のAppIcon.appiconset）
- [x] シミュレータビルド確認

### 動作確認 [人間👨‍💻]
- [ ] Xcode で実機ビルド・インストール
- [ ] 全機能の動作確認（本番APIに接続）

## ログ
### 試したこと・わかったこと
- Swift 6 strict concurrency: `@Observable` + `@MainActor` の ViewModel に actor `APIClient` を組み合わせ
- XcodeGen はファイル追加後に `xcodegen generate` を再実行しないと新しいファイルがプロジェクトに含まれない
- `AnyCodable` に `NSNull` 対応を追加して nullable フィールド（section_id, due_date）の null 送信に対応
- セクションのドラッグ&ドロップUI は SwiftUI の制約で複雑なため後日対応とした

### 方針変更
- Phase 5 の CommentList.swift は独立ファイルではなく TaskDetailSheet 内に CommentRow として組み込んだ（画面遷移が不要なため）
- Phase 6 のプロジェクト管理は TabView の contextMenu ではなくツールバーの Menu から操作する形に変更（TabView のタブ自体に contextMenu を付けるのが SwiftUI で困難なため）
