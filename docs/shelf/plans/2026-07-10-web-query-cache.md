# Web に TanStack Query ＋ localStorage キャッシュ層を導入

## 概要・やりたいこと

Web アプリ（apps/web）は開くたびにゼロから API を叩いて「読み込み中...」を表示している。TanStack Query ＋ localStorage persister を導入し、**起動時は前回のキャッシュを即描画 → 裏で再取得して差し替え（stale-while-revalidate）** にして体感速度を改善する。

あわせて既知の「遅く見える」要因（CLAUDE.md 記載）を解消する:

- `refreshKey` 変更のたびに ProjectView が remount されフル再取得になる問題 → `invalidateQueries` に置き換えて remount を撤去
- 初回ロードで sections をプロジェクト数ぶん N+1 取得している問題（`App.tsx` refreshMeta） → API に全プロジェクト横断の `GET /sections` を追加して 1 リクエスト化

## 前提・わかっていること

- **移行範囲はハイブリッド**（/dig-lite で決定）: useQuery で取得・キャッシュ表示し、結果を ProjectView の local state に同期。D&D・楽観的更新の既存ロジック（`setTasks` ベース）は無改修で残す。書き込み後は `invalidateQueries` で収束させる
- **API 改修も今回のスコープに含める**（/dig-lite で決定): `GET /sections` 追加 ＋ デプロイ
- 書き込み主体はユーザー本人のみ（個人アプリ）。古いキャッシュを一瞬見せるリスクは実質ゼロ
- フォーカス時の再取得は `App.tsx:75-87` に自前実装済み → TanStack Query の `refetchOnWindowFocus`（デフォルト有効）に置き換えて削除する
- 楽観的更新（タスク追加・削除・D&D 並べ替え）は `ProjectView.tsx` に自前実装済み。local state が in-flight の間は query data は変わらないので、「mutation を await → invalidate」の順なら上書き事故は起きない
- API 呼び出し箇所: Shell（projects / upcoming / sections）、ProjectView（sections / tasks）、ArchiveView（archived）、TaskDetail（comments 等）、Fab・TabNav（projects CRUD）
- TaskDetail のコメント取得はモーダルを開いたときの単発 fetch であり起動速度に関係しないため、今回は query 化を見送る
- 通信遅延調査（`slow-requests` ログ、`apps/web/src/lib/api.ts`）は継続中。計測は fetch 層にあるので query 化後も裏の refetch にそのまま効く。**ログの仕組みは触らない**
- Hono の auth ミドルウェアは `app.use("/sections/*", auth)`（`apps/api/src/index.ts:33`）。パターン `/sections/*` が `/sections`（末尾スラッシュなし）にマッチするか要確認 — マッチしない場合は `app.use("/sections", auth)` を追加する
- 追加パッケージ: `@tanstack/react-query`, `@tanstack/react-query-persist-client`, `@tanstack/query-sync-storage-persister`

## 実装計画

### Phase 1: API — GET /sections 追加 [AI🤖]

- [x] `apps/api/src/routes/sections.ts` に `GET /sections`（全プロジェクト横断、`ORDER BY project_id, position`）を追加
- [x] auth ミドルウェアが `/sections`（ワイルドカードなしパス）に効いているか確認。効いていなければ `apps/api/src/index.ts` に `app.use("/sections", auth)` を追加
- [x] ローカルで確認（`wrangler dev` ＋ curl: 認証なし 401 / 認証あり 200 で全 sections が返る）
- [x] `mise run deploy` で本番デプロイ → 本番エンドポイントにも curl で疎通確認

### Phase 2: Web — TanStack Query 導入とメタ取得の query 化 [AI🤖]

- [x] パッケージ追加（`@tanstack/react-query` / `react-query-persist-client` / `query-sync-storage-persister`）
- [x] `main.tsx`（または App.tsx）で `QueryClient` を生成し `PersistQueryClientProvider` でラップ
  - persister: `createSyncStoragePersister({ storage: localStorage })`、キーはデフォルトと衝突しない専用名（例 `todo-shelf-query-cache`）
  - `staleTime: 30_000`、`gcTime` は persister の `maxAge`（例 7日）と整合させる
- [x] クエリキー設計: `["projects"]` / `["sections"]`（全プロジェクト分） / `["upcoming"]` / `["tasks", projectId]` / `["archived"]`
- [x] Shell の `refreshMeta` を useQuery ×3（projects / upcoming / sections）に置き換え。sections は新設 `GET /sections` を使い N+1 を解消
- [x] 起動時の全画面「読み込み中...」はキャッシュがあるときは出さない（`isLoading` はキャッシュヒット時 false になるのでそのままで良いはず。初回のみ表示される挙動を確認）
- [x] 自前のフォーカス時再取得リスナー（`App.tsx:75-87`）を削除し、`refetchOnWindowFocus`（デフォルト）に任せる
- [x] Fab / ~~TabNav~~ のプロジェクト CRUD 後は `onProjectsChange` での手動 state 更新に加えて `invalidateQueries(["projects"])` で収束させる（TabNav はどこからも import されておらず未使用のため触らない）

### Phase 3: Web — refreshKey 撤去と ProjectView / ArchiveView のハイブリッド化 [AI🤖]

- [x] ProjectView: 自前 `load()` を useQuery（`["tasks", projectId]` ＋ `["sections"]` から該当プロジェクト分を filter）に置き換え、`useEffect` で query data → local state（`tasks` / `sections`）に同期。D&D・楽観的更新のハンドラは無改修
- [x] 書き込み系ハンドラ（タスク追加・削除、セクション追加・リネーム・削除、reorder）は **API 成功を await した後に** 該当キーを invalidate（reorder の PATCH は現状 fire-and-forget なので await に変更してから invalidate。書き込み完了前の refetch とのレースを防ぐ）
- [x] ドラッグ中（`dragTypeRef` が非 null の間）は query data → local state の同期をスキップし、フォーカス refetch による上書きを防ぐ
- [x] Shell の `refreshKey` state と `key={refreshKey}` / `key={`${projectId}-${refreshKey}`}` を撤去。`handleTaskUpdate` / `handleTaskDelete` / `handleMoveToToday` は `invalidateQueries` に置き換え
- [x] ArchiveView: `load()` を useQuery（`["archived"]`）＋ local state 同期に置き換え、restore / delete 後に invalidate（`["archived"]` と `["tasks"]` 系）
- [x] `tsc -b` とビルドが通ることを確認

### 動作確認 [AI🤖]

- [x] `mise run deploy:web` 前にローカル（`vite dev`）で agent-browser を使って確認:
  - [x] API 遮断リロードでも前回データがキャッシュから即表示される（「読み込み中...」なし）
  - [x] `localStorage` の `todo-shelf-query-cache` に4クエリが永続化されている
  - [x] タスク追加 / 削除 / 詳細モーダルからのタイトル更新が remount なしで一覧に反映される
  - [ ] D&D 並べ替え（agent-browser ではドラッグ操作を再現できないため人間の目視確認に委譲。ロジック自体は無改修）
  - [x] Archive の表示（ローカルは0件表示、本番データでは未確認）
  - [ ] 「今日へ移動」（todo-app 本番への POST を伴うため自動確認は見送り。変更点は invalidate への置き換えのみ）
- [x] `GET /sections` を curl で確認（ローカル・本番とも 認証なし401 / 認証あり200）
- [x] デプロイ後、本番 URL でも確認（リクエスト4本のみ・API遮断リロードでキャッシュ描画OK）
- [x] VERIFY.md にキャッシュ層の回帰確認手順を追記

### 最終確認 [人間👨‍💻]

- [ ] 普段のブラウザで本番を開き、起動が即表示になっているか体感確認
- [ ] iOS アプリの動作に影響がないこと（API は追加のみで既存エンドポイント無変更なので、通常利用で問題なければ OK）

## ログ

### 試したこと・わかったこと
- API テスト（vitest）は変更前の main でも Tasks 系 9 件が失敗しており既存の問題。今回のスコープ外として未対応
- ESLint の `react-hooks/set-state-in-effect` が「effect 内での同期 setState」を error にするため、ArchiveView は local state を持たず query data 直参照 ＋ `setQueryData` で楽観的削除する構成に変更（D&D がないので問題なし）。ProjectView 側の同期 effect は同ルールに引っかからなかったのでそのまま
- Toast.tsx の `react-refresh/only-export-components` lint error は既存（今回未変更ファイル）
- ProjectView の local state 初期値は `useState(() => queryData ?? [])` でキャッシュから即席込みできる（親の `key={projectId}` remount と組み合わせ、effect 待ちの空表示フラッシュを回避）

### 方針変更
- TabNav はどこからも import されていない未使用コンポーネントだったため、プロジェクト CRUD の invalidate 対応は Fab のみ実施
