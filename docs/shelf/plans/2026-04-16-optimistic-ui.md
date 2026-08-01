# 楽観的UI（Optimistic UI）の導入

## 概要・やりたいこと

タスクの作成・更新・削除時にAPIレスポンスを待たずUIに即座に反映し、操作の体感速度を改善する。現状はすべてのミューテーションでAPIレスポンスを待ってからUI更新しているため、ネットワークレイテンシ分のラグが発生している。Todoistのようにストレスのない操作感を実現したい。

失敗時はロールバック＋リトライ付きトーストで通知する。

## 前提・わかっていること

- **対象操作**: タスクの作成・更新・削除（セクション操作やコメントは今回スコープ外）
- **エラー時挙動**: ロールバック + リトライ付きトースト通知
- **再試行時**: 楽観的UIを再度適用（体験を一貫させる）
- **D&D並べ替え**: Web・iOS ともに既に楽観的UI済み（スコープ外）
- **Web**: React + useState で状態管理。トースト/通知コンポーネントなし。ライブラリ導入なしで自前実装
- **iOS**: SwiftUI @Observable + async/await。エラー表示は SwiftUI バナーで実装
- **Web・iOS 同時に進める**

### 現状のミューテーションパターン（Web）
- `apps/web/src/components/ProjectView.tsx`: タスク作成(L100-106)、削除(L109-111)、更新はTaskDetail経由
- すべて `await api.xxx()` → `setTasks()` の順

### 現状のミューテーションパターン（iOS）
- `apps/ios/Sources/ViewModels/ShelfViewModel.swift`: createTask(L147-153)、deleteTask(L171-177)、updateTask(L156-168)
- すべて `try await api.xxx()` → state更新の順

## 実装計画

### Phase 1: Web - トーストコンポーネント作成 [AI🤖]
- [x] `apps/web/src/components/Toast.tsx` を作成（メッセージ + リトライボタン + 自動消去）
- [x] トースト状態管理用の Context を作成
- [x] App.tsx にToastProviderをマウント

### Phase 2: Web - タスク操作の楽観的UI化 [AI🤖]
- [x] タスク作成: 仮IDで即座にUIに追加 → API成功で本物のタスクに差し替え、失敗でロールバック+トースト
- [x] タスク削除: 即座にUIから除去 → 失敗で元に戻す+トースト
- [x] タスク更新（タイトル・期日）: 即座にUIに反映 → 失敗で元の値に戻す+トースト

### Phase 3: iOS - エラーバナーコンポーネント作成 [AI🤖]
- [x] `ToastOverlay.swift` リトライ付きバナー表示の仕組みを作成（SwiftUI overlay）
- [x] ShelfViewModel に `ToastItem` + `toasts` 状態管理を追加
- [x] ContentView.swift にToastOverlayをマウント

### Phase 4: iOS - タスク操作の楽観的UI化 [AI🤖]
- [x] タスク作成: 仮IDで即座にstate追加 → API成功で差し替え、失敗でロールバック+バナー
- [x] タスク削除: 即座にstateから除去 → 失敗で復元+バナー
- [x] タスク更新: 即座にstate更新 → 失敗で復元+バナー

### ビルド確認 [AI🤖]
- [x] Web: vite build 成功
- [x] iOS: xcodebuild 成功（warning 1件のみ、既存）

### 動作確認 [人間👨‍💻]
- [x] Web: タスク作成・更新・削除が即座にUIに反映されることを確認
- [x] Web: ネットワークエラー時にロールバック+トーストが表示されることを確認（DevToolsでoffline or throttling）
- [x] Web: トーストのリトライボタンが機能することを確認
- [x] iOS: タスク作成・更新・削除が即座にUIに反映されることを確認
- [x] iOS: エラー時にロールバック+バナーが表示されることを確認

## ログ
### 試したこと・わかったこと
（実装中に随時追記）

### 方針変更
（実装中に随時追記）
