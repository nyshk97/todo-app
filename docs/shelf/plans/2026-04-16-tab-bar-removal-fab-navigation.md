# タブバー廃止 & FABナビゲーション導入

## 概要・やりたいこと

現状のタブバー（TODO / Deck / Vault / Archive）を廃止し、メイン画面「Shelf」を全画面表示にする。低頻度の Vault・Archive へのアクセスはフローティングアクションボタン（FAB）のメニューに集約する。

背景:
- TODOタブは期日管理で代替できるため不要
- Vault・Archive は Deck に対して使用頻度が極端に低い（5/100, 3/100）
- タブバーが画面スペースを圧迫している

## 前提・わかっていること

- タブは Project モデルから動的生成。Archive だけ特殊（`__archive__` センチネル）
- Web: React Router + `TabNav` コンポーネント（`apps/web/src/components/TabNav.tsx`）
- iOS: SwiftUI `TabView`（`apps/ios/Sources/Views/ContentView.swift`）
- プロジェクト名の変更は DB 上の Project レコードの name を更新するだけ
- 将来のプロジェクト追加の可能性は残すが、当面は考慮不要

### UI 設計の決定事項

- **メイン画面**: Shelf（旧 Deck）をタブバーなし全画面表示
- **ヘッダー**: Shelf 画面は左に「Shelf」のみ、右は空。Vault/Archive 画面は左に「← Shelf」+ 画面名
- **FAB**: 右下に「…」（ellipsis）アイコン。タップでメニュー展開（Vault / Archive / 設定）
- **FAB バッジ**: Vault 内に期限3日以内のタスクがあれば数字バッジ表示
- **FAB 表示**: Shelf 画面のみ。Vault/Archive 画面では非表示
- **期限ハイライト**: タスク行全体に薄い背景色（3日以内: オレンジ系、overdue: 赤系）
- **ナビゲーション**: Vault/Archive は push/pop（Web: ルーティング、iOS: NavigationStack）
- **実装順序**: Web → iOS

## 実装計画

### 事前準備 [人間👨‍💻]
- [x] TODO プロジェクト内のタスクを手動で整理（Deck に移動 or 削除）
- [x] TODO プロジェクトを削除

### Phase 1: Web — タブバー廃止 & FAB & メニュー遷移 [AI🤖]
- [x] `TabNav` コンポーネントを廃止し、シンプルなヘッダー（画面名のみ）に置き換え
- [x] FAB コンポーネントを作成（右下固定、「…」アイコン、タップでメニュー展開）
- [x] メニュー項目: Vault / Archive / 設定（プロジェクト管理）
- [x] Vault・Archive 画面のヘッダーに「← Shelf」戻るボタンを追加
- [x] ルーティング調整（デフォルトで Shelf プロジェクトを表示）
- [x] FAB は Shelf 画面のみ表示（Vault/Archive では非表示）

### Phase 2: Web — 期限ハイライト & Vault バッジ [AI🤖]
- [x] タスク行に期限ベースの背景色を追加（3日以内: オレンジ系、overdue: 赤系）
- [x] Vault 内の期限3日以内タスク数を取得するロジック追加
- [x] FAB に Vault バッジ（数字）を表示

### Phase 3: Web — Deck → Shelf リネーム [AI🤖]
- [x] DB 上の Project name を「Deck」→「Shelf」に更新 → UIのリネーム機能で手動変更
- [x] コード内のデフォルトプロジェクト判定ロジックを更新（`"Shelf"` 優先、`"Deck"` フォールバック）

### Phase 4: iOS — タブバー廃止 & FAB & メニュー遷移 [AI🤖]
- [x] `TabView` を `NavigationStack` ベースに置き換え
- [x] メイン画面を Shelf プロジェクトの `ProjectView` に固定
- [x] FAB コンポーネントを作成（右下固定、`ellipsis`、タップでメニュー）
- [x] メニュー項目: Vault / Archive
- [x] Vault・Archive 画面は NavigationStack の push で遷移（標準の戻るボタン）
- [x] FAB は Shelf 画面のみ表示

### Phase 5: iOS — 期限ハイライト & Vault バッジ [AI🤖]
- [x] タスク行に期限ベースの背景色を追加
- [x] FAB に Vault バッジを表示

### Phase 6: iOS — Deck → Shelf リネーム対応 [AI🤖]
- [x] デフォルトプロジェクト判定ロジックを更新（`"Shelf"` 優先、`"Deck"` フォールバック）
- [x] ~~`tabIcon` 関数の Deck 分岐を Shelf に変更~~ → TabView 廃止により不要

### 動作確認 [人間👨‍💻]
- [ ] Web: Shelf 画面が全画面表示、FAB からメニュー展開、Vault/Archive 遷移と戻る操作
- [ ] Web: 期限近いタスクの背景色ハイライト確認
- [ ] Web: Vault に期限近いタスクがあるとき FAB バッジ表示確認
- [ ] iOS: 同上の動作確認（実機ビルド）

## ログ
### 試したこと・わかったこと
（実装中に随時追記）

### 方針変更
（実装中に随時追記）
