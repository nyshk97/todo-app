# 実装計画

## Phase 1: プロジェクト基盤 ✅

### 1-1. モノレポ初期化 ✅

- `git init`
- `.gitignore` 作成（node_modules, .wrangler, .build, DerivedData 等）
- ルートに `package.json` 作成（npm workspaces で `apps/*` と `packages/*` を管理）
- ディレクトリ構造を作成

```
/apps
  /api
  /ios
  /macos
/packages
  /shared
```

### 1-2. apps/api セットアップ ✅

- `wrangler init` 相当の構成を手動で作成
  - `package.json`（hono, wrangler, typescript 等）
  - `tsconfig.json`
  - `wrangler.toml`（D1 バインディング含む）
  - `src/index.ts`（Hono アプリのエントリポイント）
- `npm install`
- `wrangler dev` でローカル起動を確認

### 1-3. packages/shared セットアップ ✅

- `package.json`
- `tsconfig.json`
- `src/types.ts` — Todo の型定義
  - `id`, `title`, `date`, `completed`, `position`, `carried_over`, `created_at`, `updated_at`

---

## Phase 2: DB とマイグレーション ✅

### 2-1. D1 データベース作成 ✅

```bash
wrangler d1 create todo-app-db
```

- database_id: `7804f6e8-8e57-4ae8-b857-da24d7f6897a`
- リージョン: APAC

### 2-2. 初期マイグレーション作成 ✅

`apps/api/migrations/0001_create_todos.sql`

### 2-3. マイグレーション適用 ✅

- ローカル・リモート両方に適用済み

---

## Phase 3: API 実装 ✅

### 3-1. 認証ミドルウェア ✅

- Bearer トークン検証ミドルウェア (`src/auth.ts`)
- `wrangler secret put API_SECRET` でシークレット登録済み
- 全エンドポイントに適用

### 3-2. GET /todos?date=YYYY-MM-DD ✅

- 指定日のタスク一覧を返す
- date 未指定時は今日の日付をデフォルトにする
- **今日の場合のみ**: 自動繰り越し処理を実行
- レスポンス: タスク一覧 + 日付の編集可否フラグ

### 3-3. POST /todos ✅

### 3-4. PATCH /todos/:id ✅

### 3-5. DELETE /todos/:id ✅

### 3-6. PATCH /todos/reorder ✅

### 3-7. テスト ✅

- date ユーティリティのユニットテスト (9件)
- Miniflare を使った API 統合テスト (16件)
- 全25テスト pass

### 3-8. デプロイ ✅

- URL: `https://todo-app-api.d0ne1s-todo.workers.dev`
- curl で本番動作確認済み

---

## Phase 4: iOS アプリ 🚧

### 4-1. Xcode プロジェクト作成 ✅

- XcodeGen (`project.yml`) でプロジェクト生成（GUI 操作なし）
- `xcodegen generate` → `.xcodeproj` 生成
- シミュレータ (iPhone 17 Pro) でビルド・起動確認済み

### 4-2. API クライアント ✅

- `URLSession` ベースの `APIClient` (actor)
- Bearer トークンをヘッダに付与
- レスポンスを Swift の `Codable` モデルにデコード

### 4-3. メイン画面（今日のタスク） ✅

- 日付ヘッダー（"Today" + 日付文字列）
- タスクリスト（未完了 / 完了をセクション分け、`ScrollView` + `LazyVStack`）
- リスト末尾にインライン入力欄（"Add a task"）で連続追加可能
- チェックボックスタップで完了切替
- 長押しコンテキストメニューから削除

### 4-4. 日付ナビゲーション（横スワイプ） ✅

- `DragGesture` で横スワイプ実装
- 左スワイプで前日、右スワイプで翌日（今日まで）
- 日付ヘッダーの表示切替（"Today" / "Yesterday" / 日付）
- 2日以上前は編集UI非表示（入力欄非表示、チェックボックス無効化）

### 4-5. ドラッグ&ドロップ並べ替え ✅

- `onDrag` + `DropDelegate` で実装（行のどこを長押ししてもドラッグ可能）
- ドラッグ中のアイテムは半透明表示
- ドロップ完了時に API に position を同期
- DB に並び順が保存され、再起動後も維持される

### 4-6. 動作確認

- [x] シミュレータでビルド・起動
- [ ] タスクの追加・完了・削除・並べ替えを実際に操作して確認
- [ ] 日付スワイプの動作確認
- [ ] 実機（iPhone）にインストールして確認

---

## Phase 5: macOS アプリ

### 5-1. Xcode プロジェクト作成

- `apps/macos/` に XcodeGen でプロジェクト生成
- iOS と共通のモデル・API クライアントコードは可能な範囲でコピー or Swift Package で共有

### 5-2. メイン画面

- iOS とほぼ同じ構成
- 日付ナビゲーションは左右の矢印ボタン（スワイプではなく）
- macOS らしいウィンドウサイズ・レイアウト調整

### 5-3. 動作確認

- ビルド・起動して動作確認
- iOS と同じデータが表示されることを確認

---

## Phase 6: iOS ウィジェット

### 6-1. WidgetKit Extension 追加

- iOS プロジェクトに Widget Extension を追加
- 大サイズ（systemLarge）のウィジェット
- 今日のタスク一覧を表示

### 6-2. Timeline Provider 実装

- API から今日のタスクを取得
- 定期的にタイムラインを更新

### 6-3. 動作確認

- シミュレータ・実機でウィジェットの表示確認

---

## Phase 7: macOS 配布（brew tap）

### 7-1. ビルドスクリプト作成

- Release ビルド → .app を zip 化
- GitHub Release にアップロード

### 7-2. Homebrew Tap リポジトリ作成

- Formula 作成
- `brew install` で動作確認

---

## 注意事項

- XcodeGen を使うことで Xcode の GUI 操作なしでプロジェクト生成が可能
- コード編集・ビルド・実機インストールは `xcodebuild` CLI で完結
- 各 Phase 完了時にコミット・動作確認を行う
- API は Phase 3 完了時点で本番デプロイ済み。クライアントは本番 API に接続する
