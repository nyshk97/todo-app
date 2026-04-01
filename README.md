# Todo App

DayTask にインスパイアされた個人用 ToDo アプリ。iOS / macOS / API のモノレポ構成。

## スクリーンショット

<!-- TODO: スクリーンショットを追加 -->

## 構成

| コンポーネント | 技術 | パス |
|---|---|---|
| API | Hono + Cloudflare Workers + D1 | `apps/api/` |
| iOS アプリ | SwiftUI + WidgetKit | `apps/ios/` |
| macOS アプリ | SwiftUI (メニューバー常駐) | `apps/macos/` |

## 機能

- タスクの追加・編集・削除・完了
- ドラッグ&ドロップで並び替え
- 日付ごとのタスク管理、前日の未完了タスクを自動繰り越し
- iOS ウィジェット
- macOS メニューバー常駐フローティングパネル

## macOS アプリのインストール

```bash
brew install nyshk97/tap/todo-mac
```

署名なしアプリのため、初回起動時にシステム設定 > プライバシーとセキュリティから許可が必要です。

## 開発

### 前提条件

- Node.js
- Xcode
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- [Wrangler](https://developers.cloudflare.com/workers/wrangler/)

### セットアップ

```bash
npm install

# Xcode プロジェクト生成（要 .env ファイル）
bash scripts/generate-projects.sh
```

各 `apps/ios/.env` と `apps/macos/.env` に `DEVELOPMENT_TEAM=<Your Team ID>` を設定してください。

### API

```bash
cd apps/api
npm run dev     # ローカル開発サーバー
npm test        # テスト実行
npx wrangler deploy  # デプロイ
```

### リリース

```bash
bash scripts/build.sh          # macOS アプリをビルド
bash scripts/release.sh 1.x.0  # GitHub Release 作成
```
