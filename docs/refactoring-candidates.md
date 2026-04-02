# リファクタリング候補

調査日: 2026-04-02

## 1. iOS / macOS 間の Swift コード重複（優先度: 高）

4ファイルが完全同一、2ファイルが 95%以上同一で、合計 370行以上が重複している。

### 完全同一のファイル

| ファイル | 行数 |
|---------|------|
| `APIClient.swift` | 108行 |
| `Todo.swift` | 26行 |
| `LinkedText.swift` | 26行 |
| `Secrets.swift`（自動生成） | 4行 |

### ほぼ同一のファイル

| ファイル | 差分 |
|---------|------|
| `TodoViewModel.swift`（~160行） | iOS のみ各ミューテーション後に `reloadWidget()` を呼ぶ |
| `Theme.swift`（~50行） | macOS のみ `closeButtonBackground` プロパティを追加 |

### 対応案

- ローカル Swift Package を作成し、共通コードを抽出する
- `TodoViewModel` は `postMutation()` フックを用意し、iOS サブクラスで `reloadWidget()` を呼ぶ
- `Theme.swift` は `closeButtonBackground` を Optional にするか、macOS 側で extension として追加する
- `Secrets.swift` は自動生成なので現状維持で OK

---

## 2. iOS Widget の API クライアント重複（優先度: 中）

`Widget/WidgetAPIClient.swift`（35行）がメインの `APIClient.swift`（108行）の簡易版。以下が重複：

- ベース URL のハードコード
- Authorization ヘッダー設定
- HTTP レスポンス検証ロジック
- Todo レスポンスモデル（`WidgetTodoResponse` vs `Todo`）

### 対応案

- 共通 Swift Package に API クライアントを移動すれば、Widget からも参照可能になる
- Widget 専用のモデル（`WidgetTodoResponse`）は不要になる

---

## 3. API `todos.ts` のコード重複（優先度: 高）

`apps/api/src/todos.ts`（220行）に 4 つの重複パターンがある。

### 3-1. Todo レスポンス変換（3箇所）

```typescript
{
  ...row,
  completed: value === 1,
  carried_over: value === 1,
  completed_at: value ?? null,
}
```

### 3-2. ID で Todo 取得（2箇所）

```typescript
const todo = await c.env.DB
  .prepare("SELECT * FROM todos WHERE id = ?")
  .bind(id)
  .first<Record<string, unknown>>();
```

### 3-3. 編集可能チェック（2箇所）

```typescript
if (!isEditable(todo.date as string)) {
  return c.json({ error: "..." }, 403);
}
```

### 3-4. 更新後の再取得（2箇所）

INSERT/UPDATE 後に同じ SELECT で取り直している。

### 対応案

- `formatTodoResponse(row)` ヘルパー関数を抽出
- `getTodoById(db, id)` ヘルパー関数を抽出
- 編集可能チェックはミドルウェアまたは共通関数に切り出し

---

## 4. API の型安全性（優先度: 中）

- D1 の行データを `Record<string, unknown>` で受け取り、各所でインラインキャストしている
- `packages/shared` に型定義があるのに API 側で活用されていない

### 対応案

- D1 の行データ用に `TodoRow` インターフェースを定義
- キャストを `formatTodoResponse()` 内に集約する

---

## 5. API のエラーハンドリング（優先度: 低）

- DB 操作に try-catch がない
- reorder エンドポイントで無効な ID のバリデーションがない
- リクエストボディのバリデーションが `title` のみ

### 対応案

- Hono の `onError` ハンドラーで共通エラーハンドリングを追加
- 入力バリデーションを強化（position、date フォーマットなど）

---

## 6. ContentView の肥大化（優先度: 低）

iOS（269行）/ macOS（267行）とも、1ファイルに複数の責務が集中している。

含まれる責務：
- ヘッダー（日付ナビゲーション）
- タスクリスト表示
- インライン入力
- タスク行コンポーネント
- チェックボックス
- ドラッグ&ドロップ（`TodoDropDelegate`）

### 対応案

- `TodoRowView`、`HeaderView` などサブコンポーネントに分割
- チェックボックスをサイズパラメータ付きの共通コンポーネント `CheckboxView` にする
- #1 の共通 Swift Package と組み合わせれば、iOS/macOS で共有可能

---

## 着手の順序（推奨）

1. **#3 API `todos.ts` のヘルパー関数抽出** — 小さい変更で効果が高い
2. **#4 API の型安全性向上** — #3 と一緒にやると効率的
3. **#1 共通 Swift Package 抽出** — 最大の重複解消だが影響範囲が広い
4. **#2 Widget API クライアント統合** — #1 の一部として対応
5. **#6 ContentView 分割** — #1 と合わせて進めると良い
6. **#5 API エラーハンドリング** — 個人利用なので優先度低め
