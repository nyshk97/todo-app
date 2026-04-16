# セクション間D&D・コメント複数行入力・コメントマークバグ修正

## 概要・やりたいこと
3つの改善をまとめて実装する:
1. **セクション間ドラッグ＆ドロップ**: 同じプロジェクト内でタスクを別セクションにドラッグ移動できるようにする（Todoist 同等の体験）
2. **コメント複数行入力**: コメント入力欄を textarea にし、改行を含むコメントを書けるようにする
3. **バグ修正**: コメント追加/削除後にタスク一覧のコメントマーク（アイコン+件数）がリロードするまで更新されない問題を修正

## 前提・わかっていること
- dnd-kit を使用中。現状は各 `SectionView` が独立した `DndContext` を持ちセクション内並べ替えのみ対応
- セクションの並べ替えは `ProjectView` の別の `DndContext` で管理
- タスク移動の API として `PATCH /tasks/reorder` が存在するが、`section_id` の変更には未対応
- コメント入力は `<input>` (1行) で実装されている（`TaskDetail.tsx:587`）
- コメント追加後に `onUpdate` が呼ばれていないため `task.comment_count` が親に伝播しない（バグの原因特定済み）
- コメント削除時も同様に `comment_count` が更新されていない

### 設計決定事項（/dig で合意済み）
- `ProjectView` に1つの `DndContext` を置き、セクション・タスク両方を管理
- `id` にプレフィックス（`section-` / `task-`）で種類を判別
- タスクはドロップした位置に挿入（末尾追加ではない）
- 空セクションには `useDroppable` でドロップ可能にする
- 未所属エリアもドロップ先として対応
- API: `PATCH /tasks/reorder` を拡張し `items` に `section_id` を含められるようにする
- コメント: Enter で改行、Cmd+Enter で送信
- ドラッグ中のビジュアルはデフォルトの挿入スペースのみ（セクションハイライトなし）

## 実装計画

### Phase 1: バグ修正 — コメントマーク即時反映 [AI🤖]
- [x] `TaskDetail.tsx` の `handleAddComment` 末尾で `onUpdate({ ...task, comment_count: task.comment_count + 1 })` を呼ぶ
- [x] コメント削除時（`handleDeleteComment`）にも `onUpdate({ ...task, comment_count: task.comment_count - 1 })` を追加
- [x] 動作確認: コメント追加/削除後にタスク一覧のアイコン+件数が即時更新されることを確認

### Phase 2: コメント複数行入力 [AI🤖]
- [x] `TaskDetail.tsx` のコメント入力を `<input>` → `<textarea>` に変更
- [x] キーバインド変更: Enter で改行、Cmd+Enter で送信
- [x] textarea の高さ自動調整（内容に応じて伸縮、最大高さ制限あり）
- [x] 動作確認: 複数行入力・Cmd+Enter 送信が正しく動作することを確認

### Phase 3: API 拡張 — reorder に section_id 対応 [AI🤖]
- [x] `packages/shared` の `ReorderRequest` 型に `section_id?: string | null` を追加
- [x] `apps/api` の `PATCH /tasks/reorder` ハンドラで `section_id` が含まれていれば UPDATE に含める
- [x] 動作確認: curl で section_id 付き reorder リクエストを送り、タスクのセクションが変わることを確認

### Phase 4: セクション間ドラッグ＆ドロップ [AI🤖]
- [x] `ProjectView` のDnD構造をリファクタ: セクション用・タスク用の `DndContext` を1つに統合
- [x] id にプレフィックスを付与（`section-{id}` / `task-{id}`）し、`onDragEnd` で種類を判別して分岐
- [x] 各 `SectionView` から独自の `DndContext` を削除し、タスクリストは親の DndContext に参加する形に変更
- [x] 空セクション・未所属エリアに `useDroppable` を設定し、タスク0個でもドロップ可能にする
- [x] `onDragEnd` でセクション間移動を検知し、optimistic に state 更新 → `PATCH /tasks/reorder` で永続化
- [x] セクション内の並べ替え（既存機能）が引き続き正しく動くことを確認

### 動作確認 [人間👨‍💻]
- [ ] ブラウザでセクション間タスク移動: ドラッグして別セクションの任意の位置にドロップできるか
- [ ] 空セクションへのドロップ
- [ ] 未所属 ↔ セクションありの移動
- [ ] セクション内の並べ替えが壊れていないか
- [ ] セクション自体の並べ替えが壊れていないか
- [ ] コメント複数行入力 + Cmd+Enter 送信
- [ ] コメント追加/削除後のマーク即時反映

## ログ
### 試したこと・わかったこと
- 未所属エリアの表示条件を変更: セクションがある場合でも常に表示するようにした（ドロップ先として必要）
- ローカル dev サーバーでのブラウザ確認は CORS の問題で「読み込み中...」のまま止まる（既存の問題、今回の変更とは無関係）
- TypeScript 型チェック・Vite ビルドともにエラーなし

### 方針変更
（なし）
