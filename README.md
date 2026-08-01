# Todo App

個人用タスク管理のモノレポ。2 つのプロダクトを含む。

- **todo** — [DayTask](https://apps.apple.com/jp/app/daytask-seize-your-day/id6760099687) にインスパイアされた「今日やること」の管理（iOS / macOS / API）
- **shelf** — Todoist 代替。「今すぐやらないけど忘れたくないこと」の置き場（iOS / Web / API）。todo へタスクを移動できる

## スクリーンショット

<!-- TODO: スクリーンショットを追加 -->

## 構成

| プロダクト | コンポーネント | 技術 | パス |
|---|---|---|---|
| todo | API | Hono + Cloudflare Workers + D1 | `apps/todo/api/` |
| todo | iOS アプリ | SwiftUI + WidgetKit | `apps/todo/ios/` |
| todo | macOS アプリ | SwiftUI (メニューバー常駐) | `apps/todo/macos/` |
| shelf | API | Hono + Cloudflare Workers + D1 + R2 | `apps/shelf/api/` |
| shelf | iOS アプリ | SwiftUI | `apps/shelf/ios/` |
| shelf | Web | React + Vite (Cloudflare Pages) | `apps/shelf/web/` |

共有型定義は `packages/todo-shared/`（`@todo-app/shared`）と `packages/shelf-shared/`（`@todo-shelf/shared`）。

## 機能

### todo

- タスクの追加・編集・削除・完了
- ドラッグ&ドロップで並び替え
- 日付ごとのタスク管理、前日の未完了タスクを自動繰り越し
- iOS ウィジェット
- macOS メニューバー常駐フローティングパネル

### shelf

- プロジェクト / セクション単位でのタスク管理（「完了」の概念はなく、アクションは「移動」か「削除」）
- コメント・添付ファイル（R2）・アーカイブ
- ドラッグ&ドロップでのセクション間移動と並び替え
- todo への「今日やる」移動
- iOS のオフライン対応

## macOS アプリのインストール

```bash
brew install nyshk97/tap/todo-mac
```

署名なしアプリのため、初回起動時にシステム設定 > プライバシーとセキュリティから許可が必要です。

## iOS アプリ

App Store では公開していません。利用するには Xcode でソースコードからビルドし、実機にインストールする必要があります。

## 開発

### 前提条件

- Node.js
- Xcode
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- [Wrangler](https://developers.cloudflare.com/workers/wrangler/)
- [mise](https://mise.jdx.dev/)（タスクランナー。`mise tasks` で一覧）

### セットアップ

```bash
npm install

# todo の Xcode プロジェクト生成（要 .env ファイル）
bash scripts/generate-projects.sh
```

`apps/todo/ios/.env` と `apps/todo/macos/.env` に `DEVELOPMENT_TEAM=<Your Team ID>` と `API_SECRET=<token>` を設定してください。
shelf iOS は `apps/shelf/ios/Sources/Secrets.swift` を手動で用意します（生成スクリプトは todo 専用）。

### todo

```bash
mise run todo:dev            # API ローカル開発サーバー
mise run todo:test           # API テスト
mise run todo:deploy         # API デプロイ
mise run todo:build:ios      # iOS を Xcode で開く
mise run todo:build:mac      # macOS をビルドして起動
```

### shelf

```bash
mise run shelf:dev           # API ローカル開発サーバー
mise run shelf:test          # API テスト
mise run shelf:dev:web       # Web ローカル開発サーバー
mise run shelf:deploy        # API デプロイ
mise run shelf:deploy:web    # Web デプロイ (Cloudflare Pages)
mise run shelf:build:ios     # iOS を Xcode で開く
```

### リリース（macOS アプリ）

```bash
mise run todo:build              # macOS アプリをビルド
mise run todo:release -- 1.x.0   # GitHub Release 作成
```
