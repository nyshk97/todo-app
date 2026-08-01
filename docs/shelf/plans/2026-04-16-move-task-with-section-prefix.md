# タスク移動時にセクション名をプレフィックスとして付与

## 概要・やりたいこと
Shelfからtodo-appにタスクを移動する際、セクションに所属しているタスクはタイトルの冒頭にセクション名を付けた状態で移動する。todo-appに移動した後もタスクの出自（どのカテゴリに属していたか）がわかるようにする。

## 前提・わかっていること
- フォーマット: `[セクション名] タスクタイトル`（セクションなしの場合はタイトルのみ）
- プロジェクト名は付与しない（セクション名のみ）
- todo-appへのPOSTはクライアント側（Web/iOS）で直接実行しており、API側はShelfのアーカイブのみ担当
- Web側: `App.tsx` の `handleMoveToToday` で `task.title` をそのまま送信中。セクション一覧は `sections` stateに保持済み
- iOS側: `ShelfViewModel.moveTaskToToday` で `task.title` を渡している。`sections` は ViewModel 内の辞書で管理済み
- API側のエンドポイントや送信データ構造は変更不要

## 実装計画

### Phase 1: Web側の修正 [AI🤖]
- [x] `apps/web/src/App.tsx` の `handleMoveToToday` で、`selectedTask.section_id` からセクション名を引き、`[セクション名] タイトル` を組み立ててtodo-appにPOSTする

### Phase 2: iOS側の修正 [AI🤖]
- [x] `apps/ios/Sources/ViewModels/ShelfViewModel.swift` の `moveTaskToToday` で、`task.sectionId` から `sections` を検索してセクション名を取得し、`[セクション名] タイトル` を組み立てて `api.moveTaskToToday` に渡す

### 動作確認 [人間👨‍💻]
- [ ] Web: セクションありのタスクを「今日のTODOへ移動」→ todo-appでタイトルに `[セクション名]` が付いていることを確認
- [ ] Web: セクションなしのタスクを移動 → タイトルがそのままであることを確認
- [ ] iOS: 同様の確認

## ログ
### 試したこと・わかったこと
（実装中に随時追記）

### 方針変更
（実装中に随時追記）
