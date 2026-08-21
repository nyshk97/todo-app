# Changelog

TodoMac（macOS 版 todo アプリ）の更新履歴。iOS 版と API は対象外。形式は [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) ベース、バージョニングは [SemVer](https://semver.org/lang/ja/)。

`scripts/release.sh`（`mise run todo:release`）が `[Unreleased]` を `[X.Y.Z] - YYYY-MM-DD` に切り出し、そのセクションを GitHub Release のノートと Sparkle の更新ダイアログ（appcast の `<description>`）の両方に流し込む。ここが唯一の源。

## 書き方

リリース時に Claude Code のセッションが `git log <前回タグ>..HEAD` を読んで `[Unreleased]` を埋め、commit してから `mise run release` を叩く。コミットごとには書かない。ここを読んだだけで書ける粒度で書いてある。

### 1. フォーマット

```markdown
## [Unreleased]

### ✨ Added
- メニューに「アップデートを確認…」を追加

### 🐛 Fixed
- 起動時にアクセシビリティ権限のダイアログが毎回出るのを修正
```

- 1 項目 = 1 行。継続行は書かない（HTML 変換が `- ` 始まりの単一行しか拾わない）
- インライン Markdown は `` `code` ``・`**strong**`・`[label](url)` のみ
- 体言止め（「〜を追加」「〜を修正」「〜に変更」）。主語は書かない

### 2. カテゴリ

```
✨ Added       — 新しい機能・メニュー項目・設定
📝 Changed     — 既存機能の挙動・既定値・見た目の変更
🐛 Fixed       — 期待通りに動かなかったものが直った
🗑️ Removed     — 機能・設定の削除
```

使わないカテゴリの見出しは書かない。

### 3. 書くもの・書かないもの

- **書く**: ユーザーが目で見て・触って気づく変更だけ（パネルの見た目と挙動・メニュー・同期の体感）
- **書かない**: 内部リファクタ・テスト・ドキュメント・ビルド/リリーススクリプト・CI・依存の更新
- iOS 版・API・shelf にしか影響しない変更は書かない（`git log -- apps/todo/macos packages/todo-shared` で絞る）
- 該当するものが無いリリース（配布基盤だけの修正など）は「- 内部的な変更のみ」と 1 行書く

## [Unreleased]

## [1.17.1] - 2026-08-01

### 🐛 Fixed
- タスク作成のリトライや同期の再送で同じタスクが二重登録されるのを修正

## [1.17.0] - 2026-06-04

### 🐛 Fixed
- 起動時にアクセシビリティ権限のダイアログが毎回出るのを修正

## [1.16.0] - 2026-05-20

### 📝 Changed
- パネルの表示位置をカーソル中心に変更
