# iOS セクション間ドラッグ&ドロップ対応

## 概要・やりたいこと

iOSアプリのメインのProjectView（Shelf/Backlog等）で、タスクを別セクションにドラッグ&ドロップで移動できるようにする。現状はセクション内並び替えのみサポートされており、セクション間移動は「移動」シート経由。直接D&Dで動かせるとかなり使い勝手が良くなる。

SwiftUI標準の `.onDrag`/`.onDrop` はセクション間移動に不向き（アニメーション制御の限界、スクロールとの競合）のため、`DragGesture` + `LongPressGesture` の自前実装に置き換える。同一セクション内の並び替えも新実装に統一し、旧D&Dは削除する。

## 前提・わかっていること

### 対象範囲
- メインの `ProjectView`（Shelf / Backlog 等）のみ
- Archive は対象外（既存の contextMenu / swipeActions のまま）

### 既存資産（再利用可能）
- `ShelfViewModel.moveTask(projectId:sectionId:)` L223-235: セクション間移動API（既存・再利用）
- `ShelfViewModel.reorderTasks()` L237-254: 並び替えサーバー同期（再利用）
- `ShelfViewModel.moveTaskLocally()` L357-379: ローカル配列操作（拡張して再利用）

### 置き換え対象
- `apps/ios/Sources/Views/SectionView.swift` の `TaskListView` 内 `.onDrag`/`.onDrop`（L113-123）と `TaskDropDelegate`（L197-233）

### 設計上の決定事項
- ドラッグ状態: `@StateObject DragController: ObservableObject` で一元管理、`.environmentObject` で配布
- ジェスチャ: `LongPressGesture(0.5).sequenced(before: DragGesture(coordinateSpace: .named("project")))` を TaskListView の ForEach 内 TaskRow 外側に `.simultaneousGesture` で付与
- 座標収集: `PreferenceKey` + `GeometryReader` でタスク行・セクションfameを ProjectView の CoordinateSpace に集約
- ドラッグ中描画: 元行 opacity 0.3 + ProjectView最外 `ZStack` にゴースト行を `position(x:y:)` で描画
- ドロップ先: `{ sectionId: String?, insertionIndex: Int }` の正規化形。同一セクションなら `reorderTasks`、別セクションなら `moveTask` を呼び分け
- 視覚フィードバック: ドロップ先セクション背景を薄くハイライト + 挿入位置に2ptインジケーター
- ハプティクス: ドラッグ開始（medium impact）とドロップ確定（success notification）
- オートスクロール: 画面端60pt以内で Timer 駆動の自動スクロール（ScrollView を `UIViewRepresentable` でラップ or introspect）

### TaskRow.contextMenu の扱い
- TaskRow の `.contextMenu`（現状は削除のみ）は SwiftUI 的に長押しD&Dと共存困難なため削除
- 削除は `.swipeActions(edge: .trailing)` に移行（ArchiveView と一貫）
- SectionView ヘッダーの contextMenu（セクション名変更・並び替え・削除）はタスク行ではないので影響なし、維持

### 潜在的な落とし穴
- LazyVStack + GeometryReader は `.background(GeometryReader {...})` パターン必須。素で置くと高さ計算が壊れる
- `.coordinateSpace(name:)` は ScrollView 自体ではなく LazyVStack に付ける（スクロール位置に依存しない座標系）
- `@Published CGPoint` を毎フレーム更新すると ObservableObject 全体が invalidate。ゴースト View を極小コンポーネント化して他Viewへの伝播を抑える
- Button 内 TaskRow の押下スタイル（薄灰色）が長押し中に残ると違和感。カスタム `ButtonStyle` で長押し開始時にキャンセル

## 実装計画

### Phase 1: 骨格実装（同一セクション内並び替えのみ） [AI🤖]
- [x] `apps/ios/Sources/Views/DragController.swift` 新規作成。`@Observable @MainActor` で `draggingTaskId`, `dragLocation`, `currentDropTarget`, `ghostOffset`, `isActive` を管理
- [x] `apps/ios/Sources/Views/DragPreferenceKeys.swift` 新規作成。タスク行frame・セクションframe収集用の `PreferenceKey` を定義
- [x] `ProjectView.swift` に `@State` で DragController 追加、LazyVStack に `.coordinateSpace(name: "project")` を付与、`.environment(dragController)` で子に配布、LazyVStack の overlay にゴースト描画 追加
- [x] `SectionView.swift` のセクション frame 収集（GeometryReader + PreferenceKey）
- [x] `TaskListView` に `.simultaneousGesture(LongPressGesture.sequenced(before: DragGesture))` でドラッグ判定、タスク行frame収集、元行 opacity 0.3 適用
- [x] 同一セクション内のヒットテスト実装（上/下半分方式）と `reorderTasks` 経由の並び替え
- [x] ~~旧 `.onDrag`/`.onDrop` は残したまま並走~~ → 新ジェスチャーと競合するため `.onDrag`/`.onDrop` の TaskRow への付与は削除。`TaskDropDelegate` 構造体自体は Phase 3 で削除
- [x] ドラッグ開始時の軽いハプティクス（`UIImpactFeedbackGenerator(.medium)`）

### Phase 1 動作確認 [人間👨‍💻]
- [x] Xcode で実機ビルド、同一セクション内のタスク並び替えが新D&Dで動くことを確認
- [x] タップで詳細画面が開くことを確認（ドラッグ誤発動なし）
- [x] ScrollView のスクロール挙動に問題なし

### Phase 2: セクション間移動 [AI🤖]
- [x] ヒットテストを「セクション + 挿入インデックス」に拡張（Phase 1 時点で既に対応済み）
- [x] `ShelfViewModel.moveTaskToSection(taskId:projectId:toSectionId:insertAt:)` を新規追加。updateTask API + reorderTasks API の組み合わせ、楽観更新 + エラー時ロールバック
- [x] `applyDrop` を拡張し source sectionId != target sectionId のとき moveTaskToSection を呼ぶ
- [x] ~~ドロップ先セクションの背景ハイライト~~ → Phase 1 で前倒し済み
- [x] ~~挿入位置インジケーター~~ → Phase 1 で前倒し済み
- [x] ドロップ成功時のハプティクス（`UINotificationFeedbackGenerator.success`）

### Phase 2 動作確認 [人間👨‍💻]
- [x] セクション間移動が動く
- [x] 楽観更新後、サーバー再取得でもタスク順序が保たれる
- [x] 移動中のハイライト・インジケーターが見やすい

### Phase 3: 旧D&D削除 + 削除UIの整理 [AI🤖]
- [x] `SectionView.swift` の `TaskDropDelegate` / `UniformTypeIdentifiers` import 削除（`.onDrag`/`.onDrop` は Phase 1 で既に削除済み）
- [x] `TaskRow.swift` の `UniformTypeIdentifiers` import 削除、`onDelete` パラメータ削除
- [x] `TaskListView` の `confirmDeleteTask` state / delete alert 削除（TaskRow.contextMenu 削除により未使用）
- [x] `ShelfViewModel.moveTaskLocally` 削除（TaskDropDelegate 撤去により未使用）
- [x] ~~swipeActions で削除アクション追加~~ → **`.swipeActions` は `List` 内限定のため断念**。削除手段は TaskDetailSheet の削除ボタンに一元化（ユーザー合意済み）
- [x] ~~ドロップ確定時のハプティクス~~ → Phase 2 で実装済み

### Phase 3 動作確認 [人間👨‍💻]
- [x] ~~swipe で削除が動く~~ → swipe-to-delete は実装断念のため対象外
- [x] ドラッグ中・ドロップ時のハプティクスが心地よい
- [x] 新D&D以外のタッチ操作（タップ・スクロール・セクションヘッダー長押し）が壊れていない

### Phase 4: オートスクロール + 視覚洗練 [AI🤖]
- [x] `ScrollViewFinder` 新規作成（superview を辿って UIScrollView を取得する UIViewRepresentable）
- [x] `ProjectView` の LazyVStack の background に `ScrollViewFinder` を配置、取得した UIScrollView を `dragController.scrollView` に設定
- [x] `DragController` にオートスクロール実装: 上端/下端 60pt 以内で速度決定（最大 400pt/s、端に近いほど速い）、`Swift.Task + asyncSleep` で 60fps ループ、`setContentOffset` で直接スクロール、`dragLocation.y` も同期更新してヒットテスト再計算
- [x] ~~ゴーストに shadow + scaleEffect~~ → Phase 1 で実装済み（`DragGhostView`）

### Phase 4 動作確認 [人間👨‍💻]
- [x] 画面外のセクションまでドラッグで移動できる
- [x] オートスクロール速度が快適
- [x] 急なスクロール停止等の不具合なし

## ログ

### 試したこと・わかったこと
- プロジェクトは iOS 18 + Swift 6 + `@Observable` macro (ObservableObject ではない)。DragController は `@Observable @MainActor final class` として実装、`.environment()` / `@Environment(DragController.self)` で配布
- `PreferenceKey.defaultValue` は Swift 6 の concurrency check で `static var` 禁止。`static let` にする必要あり
- Section frame 収集: sectioned は SectionView の `.background(GeometryReader)`、unsectioned は TaskListView 内で条件付きに報告する構造に
- xcodebuild clean build で `** BUILD SUCCEEDED **` 確認済み（2026-04-23）

### 方針変更
- **Phase 1 で旧 `.onDrag`/`.onDrop` を並走させる案を撤回**。新ジェスチャー（`LongPressGesture.sequenced(DragGesture)`）と SwiftUI 標準の `.onDrag` は両方とも長押しで発火するため、TaskRow に両方付けると競合して挙動が破綻する。TaskRow への `.onDrag`/`.onDrop` 付与は Phase 1 で削除した。`TaskDropDelegate` 構造体自体は未使用のまま残置（Phase 3 で削除予定）
- **TaskRow の `.contextMenu`（削除）を Phase 3 から Phase 1 に前倒し**。contextMenu と LongPressGesture が競合して、長押しで削除メニューが出てD&Dが発動しない問題が発生。TaskRow から contextMenu を削除した。swipeActions 移行は Phase 3 で別途対応（`List` 化 or カスタム横スワイプ実装）。当面の削除手段は TaskDetailSheet のみ
- **`.simultaneousGesture` → `.highPriorityGesture` に変更**。simultaneousGesture だとドロップ後に Button の tap action が発火して詳細画面が開いてしまう。highPriorityGesture にして drag 優先、短いタップ（0.4秒未満）のみ Button の onTap に通す
- **Phase 2 の視覚フィードバックを Phase 1 に前倒し**。ドロップ先がわからないと使い物にならないため。ドロップ先セクションの背景ハイライト（`Theme.accentBright.opacity(0.08)`）と挿入位置インジケーター（2pt の `Theme.accentBright` ライン）を追加
- **swipe-to-delete の実装を断念**。`.swipeActions` は `List` 内限定の制約があり、現状の VStack 構造では直接使えない。List 化は見た目への影響が大きくリスクあり、カスタム実装はコストに見合わない。削除手段は TaskDetailSheet からのみに集約する方針で合意
- **TaskRow の `Button` を撤去**。`Button` + 外側 gesture だと「simultaneousGesture なら tap も drag も発火（ドロップ後に詳細が開く）」「gesture だと Button が常勝（ドラッグ不発）」「highPriorityGesture だと drag が常勝（タップ不発）」と三択全敗。`Button` → `HStack + .onTapGesture` に変更し、`.simultaneousGesture` でドラッグと共存させると、タップ（短時間）とドラッグ（長押し）が排他的に認識されて両立
- **空セクションで挿入インジケーターが出ない問題を修正**。overlay が TaskRow に付いていたため、tasks が空だと描画されなかった。`tasks.isEmpty && isDropTarget` のとき TaskListView 先頭に2pt線を描画する分岐を追加
- **ピックアップ時ハプティックの試みを撤回**。`.first(true)` で haptic を鳴らす案を試したが、`pickedUpTaskId` フラグがジェスチャーキャンセル時にリセットされず状態汚染が発生（ハプティックが鳴るが drag が動かず、次回以降の操作も影響を受ける）。ハプティックは元の「ドラッグ開始時（初回の `.second(true, dragValue)`）」に戻した
- **ピックアップ時の視覚フィードバックは `@GestureState` で実装**。`@GestureState private var pickedUpTaskId: String?` を使い、`.updating` で LongPressGesture 完了中は `task.id` を保持。ジェスチャー終了（キャンセル含む）で自動リセットされるため状態汚染なし。ピックアップ中の行背景を `Theme.accentBright.opacity(0.12)` で染めるだけなので haptic より安全に実現できた
