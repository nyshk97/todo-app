# 実装計画

## Phase 1: プロジェクト基盤

### 1-1. モノレポ初期化

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

### 1-2. apps/api セットアップ

- `wrangler init` 相当の構成を手動で作成
  - `package.json`（hono, wrangler, typescript 等）
  - `tsconfig.json`
  - `wrangler.toml`（D1 バインディング含む）
  - `src/index.ts`（Hono アプリのエントリポイント）
- `npm install`
- `wrangler dev` でローカル起動を確認

### 1-3. packages/shared セットアップ

- `package.json`
- `tsconfig.json`
- `src/types.ts` — Todo の型定義
  - `id`, `title`, `date`, `completed`, `position`, `carried_over`, `created_at`, `updated_at`

---

## Phase 2: DB とマイグレーション

### 2-1. D1 データベース作成

```bash
wrangler d1 create todo-app-db
```

- 出力される database_id を `wrangler.toml` に記載

### 2-2. 初期マイグレーション作成

`apps/api/migrations/0001_create_todos.sql`:

```sql
CREATE TABLE todos (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  date TEXT NOT NULL,           -- YYYY-MM-DD
  completed INTEGER NOT NULL DEFAULT 0,
  position INTEGER NOT NULL DEFAULT 0,
  carried_over INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_todos_date ON todos(date);
```

### 2-3. マイグレーション適用

```bash
wrangler d1 migrations apply todo-app-db --local   # ローカル確認
wrangler d1 migrations apply todo-app-db --remote  # 本番適用
```

---

## Phase 3: API 実装

### 3-1. 認証ミドルウェア

- Bearer トークン検証ミドルウェアを作成
- `wrangler secret put API_SECRET` でシークレット登録
- 全エンドポイントに適用

### 3-2. GET /todos?date=YYYY-MM-DD

- 指定日のタスク一覧を返す
- date 未指定時は今日の日付をデフォルトにする
- **今日の場合のみ**: 自動繰り越し処理を実行
  - 今日のタスクが0件 かつ 前日に未完了タスクがある場合
  - 前日の未完了タスクを今日の日付でコピー（`carried_over = 1`）
  - 繰り越し元はそのまま残す
- レスポンス: タスク一覧 + 日付の編集可否フラグ

### 3-3. POST /todos

- 新規タスク追加
- date は今日の日付に固定（リクエストで指定不可）
- `position` は既存タスクの最大値 + 1

### 3-4. PATCH /todos/:id

- タスクの更新（title, completed, position）
- 対象タスクの date が今日または1日前でなければ 403

### 3-5. DELETE /todos/:id

- タスクの削除
- 対象タスクの date が今日または1日前でなければ 403

### 3-6. PATCH /todos/reorder

- 並び順の一括更新（`[{ id, position }]` の配列を受け取る）
- 今日のタスクのみ許可

### 3-7. 動作確認

- `wrangler dev` でローカル起動
- curl で全エンドポイントをテスト
  - タスク追加 → 一覧取得 → 完了切替 → 削除
  - 日付制限の検証（過去タスクへの更新拒否）
- デプロイ: `wrangler deploy`
- 本番 URL で同様に curl テスト

---

## Phase 4: iOS アプリ

### 4-1. Xcode プロジェクト作成

- `apps/ios/` に Swift Package として作成（CLI で `swift package init` は使わず、`xcodebuild` ベースで管理）
- ただし iOS アプリは Xcode プロジェクトが必要なため、最小限の `.xcodeproj` を作成
- SwiftUI の App エントリポイント作成

### 4-2. API クライアント

- `URLSession` ベースのシンプルな API クライアント
- Bearer トークンをヘッダに付与
- トークンは iOS の設定画面 or ハードコード（個人用なので）
- レスポンスを Swift の `Codable` モデルにデコード

### 4-3. メイン画面（今日のタスク）

- 日付ヘッダー（"Today" + 日付文字列）
- タスクリスト
  - 未完了タスク: チェックボックス + タイトル
  - 完了タスク: チェック済み + 打ち消し線 + グレーアウト（リスト下部）
- 右下に「+」ボタン → タスク追加
- チェックボックスタップで完了切替
- スワイプ削除

### 4-4. 日付ナビゲーション（横スワイプ）

- `TabView` with `.tabViewStyle(.page)` または `ScrollView` + gesture で横スワイプ実装
- 左スワイプで前日、右スワイプで翌日（今日まで）
- 日付ヘッダーの表示切替（"Today" / "Yesterday" / 日付）
- 2日以上前は編集UI非表示（「+」ボタン非表示、チェックボックス無効化）

### 4-5. ドラッグ&ドロップ並べ替え

- `List` + `.onMove` で実装
- 並べ替え後に API に position を送信

### 4-6. 動作確認

- Xcode からシミュレータで起動
- タスクの追加・完了・削除・並べ替えを確認
- 日付スワイプの動作確認
- 実機（iPhone）にインストールして確認

---

## Phase 5: macOS アプリ

### 5-1. Xcode プロジェクト作成

- `apps/macos/` に macOS アプリとして作成
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

- iOS / macOS のプロジェクト作成は Xcode の GUI 操作が最小限必要（初回のみ）
  - それ以降のコード編集・ビルド・実機インストールは `xcodebuild` CLI で可能
- 各 Phase 完了時にコミット・動作確認を行う
- API は Phase 3 完了時点で本番デプロイし、以降のクライアント開発は本番 API に接続する
