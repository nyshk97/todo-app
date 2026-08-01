# 開発メモ

このリポジトリは 2 プロダクトのモノレポ。

- **todo** — 今日やるタスク管理（API / iOS / macOS）
- **shelf** — 「今すぐやらないけど忘れたくないこと」の置き場（API / iOS / Web）。todo の補完

両者は API 経由で連携する（shelf → todo へのタスク移動）。**API 契約を変える変更は両側を 1 コミットで直せる**のがモノレポ化の狙いなので、片側だけ直して終わりにしない。

## セッション開始時の注意

- **作業を始める前に `git fetch origin` して origin/main との差分を確認する**。このリポジトリは複数の環境から push されるため、ローカルが古いまま作業すると「リモートにだけ存在する修正」を知らずに再実装したり、古いコードで実機を上書きして修正済みバグを再発させる事故が起きる（2026-07-14 に実例あり: スクロール修正 `TaskDragRecognizer` がリモートのみに存在し、古い HEAD からの実機ビルドで再発した）

## プロジェクト構成

```
apps/
  todo/
    api/      Hono + Cloudflare Workers + D1 (SQLite)
    ios/      SwiftUI iOS アプリ + WidgetKit
    macos/    SwiftUI macOS メニューバーアプリ
  shelf/
    api/      Hono + Cloudflare Workers + D1 (SQLite) + R2
    ios/      SwiftUI iOS アプリ
    web/      React + Vite (SPA)、Cloudflare Pages にデプロイ
packages/
  todo-shared/    todo の共有型定義 (@todo-app/shared)
  shelf-shared/   shelf の共有型定義 (@todo-shelf/shared)
scripts/          ビルド・リリース・プロジェクト生成スクリプト
docs/
  plans/          今後の plan 置き場（todo / shelf 共通）
  shelf/          旧 todo-shelf リポジトリ由来の docs
```

- npm workspaces は `["apps/*/*", "packages/*"]`
- shelf は 2026-08-01 に別リポジトリ（nyshk97/todo-shelf）から履歴ごと統合した。統合時に SHA を振り直しているため、旧 SHA ↔ 新 SHA の対応は `docs/shelf/migration-commit-map.txt` を引く

## よく使うコマンド

`.mise.toml` にタスク定義あり。`mise tasks` で一覧表示。タスク名は `todo:` / `shelf:` プレフィックスで製品別に分かれている（両製品にまたがる `generate` だけプレフィックスなし）。

新しい環境で clone したときや「動かない」ときは `bash scripts/check-setup.sh` を先に実行する。git 管理外の `.env` / `.dev.vars` の過不足を一覧し、不足分の用意方法を表示する（値そのものは表示しない）。

統合前から clone を持っていた環境では `bash scripts/migrate-local-secrets.sh [<旧 todo-shelf clone のパス>]` を1回実行する。**git は gitignore 対象のファイルを移動しないので、pull 後も `apps/api/.dev.vars` などが旧パスに残っている**。これを新パスへ移し、shelf 側は旧 clone からコピーする（`apps/shelf/ios/.env` は旧 clone の `Secrets.swift` と todo の `DEVELOPMENT_TEAM` から組み立てる）。既存ファイルは上書きしないので何度実行してもよい。

---

# todo（`apps/todo/`）

## API

- 本番: `https://todo-app-api.d0ne1s-todo.workers.dev`
- 認証: `Authorization: Bearer <API_SECRET>`（値は `.env` で管理）
- DB マイグレーション: `apps/todo/api/migrations/` に SQL ファイルを追加し `mise run todo:deploy:migrate`（= `npx wrangler d1 migrations apply todo-app-db --remote`）で適用
- テストの DB スキーマ: `apps/todo/api/src/__tests__/api.test.ts` 内に直書き。マイグレーション追加時はここも更新すること
- 日付は JST (UTC+9) で計算。`apps/todo/api/src/date.ts` の `toJST()` ヘルパーを使用
- D1 の prepared statement で `null` をバインドしても値がクリアされない。`column = NULL` と raw SQL で書くこと

## iOS アプリ

- XcodeGen で `project.yml` からプロジェクト生成。`.xcodeproj` は gitignore 対象
- `apps/todo/ios/.env` に `DEVELOPMENT_TEAM=<Team ID>` を設定（git 管理外）
- Apple Developer Program（個人）で署名。Xcode の自動署名を使用
- ウィジェットのバンドル ID: `com.d0ne1s.todoapp.widget`
- WidgetKit 更新: ViewModel 内で `WidgetCenter.shared.reloadAllTimelines()` を呼ぶ
- `LazyVStack` で同じ ID を複数の `ForEach` で使うとキャッシュバグが起きる。完了済みタスクには `.id("done-\(todo.id)")` で回避
- `contextMenu` は dimming バグがあるので使わない。タスク名タップで編集、ゴミ箱アイコンで即削除
- `onTapGesture` と `onDrag` は共存可能だが、`onLongPressGesture` と `onDrag` は競合する
- iOS の `PendingOperation` 同期では、同期開始時に fetch した配列 snapshot を最後まで回さない。同期中に ViewModel 側で op が削除・相殺される race があるため、各 iteration で次の pending op を SwiftData から取り直す。HTTP 400/403/409 など再試行で解消しない op は先頭で詰まらせず、ユーザーに見える同期エラーを残して drop する
- 実機インストール: 基本は Xcode で実機を選んで Cmd+R でよい。有料 Apple Developer Program の Development profile は1年有効（2026-08 に embedded.mobileprovision の ExpirationDate で実測確認済み）。「約1週間で期限切れ」は無料 Apple ID（Personal Team）時代の制限で、現在は該当しない。長期運用向けに Ad Hoc export する場合: `mise run todo:build:ios` で Xcode を開き、Product > Archive → Distribute App > Release Testing (Ad Hoc) で .ipa を export → Devices and Simulators に .ipa をドラッグ
- `GENERATE_INFOPLIST_FILE: true` と `info:` (path なし) は XcodeGen で併用不可。カスタム値は `Secrets.swift` の自動生成で対応
- XcodeGen で新規ファイルを追加すると SourceKit が一時的に偽陽性エラー（`Cannot find type X in scope` 等）を出すが、これは `.xcodeproj` 未再生成によるもの。`bash scripts/generate-projects.sh` 後に解消する。多数表示されてもひるまず、最後に `xcodebuild ... -sdk iphonesimulator build` で実ビルドして確認する

## macOS アプリ

- メニューバー常駐 + フローティングパネル形式（`NSPanel`）
- `KeyablePanel` サブクラスで `canBecomeKey` を有効にしないとテキスト入力ができない
- `styleMask` に `.titled` や `.hudWindow` を含めるとダークなタイトルバーが出る。ボーダーレスにして角丸背景 + カスタム×ボタンで対応
- パネル表示時に `NotificationCenter` 経由でデータを再読み込み
- 署名なしでビルド: `CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO`
- `isMovableByWindowBackground = true` だと `onDrag` が奪われる。ヘッダーのみに `WindowDragView`（NSViewRepresentable）を配置して対応
- 「コードにあるはずの機能が見えない」場合はまず起動中バイナリが最新か疑う: `ps aux | grep TodoMac` で実行パスを確認し、DerivedData の mtime と比較する。古いキャッシュビルドを起動していることが原因の場合がある
- Accessibility 権限はバンドルパスと署名に紐づく。未署名ビルド (`CODE_SIGN_IDENTITY="-"`) を `scripts/build.sh` で作り直したり brew で `/Applications/` 側に移ったりすると別アプリ扱いになり、System Settings → Privacy & Security → Accessibility で再付与が必要になる。グローバルホットキーが効かなくなったらまずここを疑う

## ビルド・リリース

- `bash scripts/generate-projects.sh` - **3つの Xcode プロジェクト（todo iOS / todo macOS / shelf iOS）をまとめて生成**（各アプリの `.env` の Team ID をプレースホルダーに置換、`Secrets.swift` を自動生成）
- `apps/todo/{ios,macos}/.env` と `apps/shelf/ios/.env` に `DEVELOPMENT_TEAM=<Team ID>` と `API_SECRET=<token>` を設定。`.env` も `Secrets.swift` も gitignore 対象なので、新しい環境では手で用意する（`.env` さえ置けば `Secrets.swift` は生成される）
- `bash scripts/build.sh` - macOS アプリを Release ビルドして zip 化
- `bash scripts/release.sh <version>` - `MARKETING_VERSION` 自動更新 → Release ビルド → GitHub Release 作成 → homebrew-tap の Cask 更新 → ローカル tap 同期まで自動実行

## Brewfile

`~/Library/CloudStorage/Dropbox/Brewfile` に `cask 'nyshk97/tap/todo-mac'` を記載済み

---

# shelf（`apps/shelf/`）

## コンセプト

- Todoist 代替。「今すぐやらないけど忘れたくないこと」を管理する場所
- todo（今日やるタスク管理）の補完アプリ
- タスクに「完了」の概念はない。アクションは「移動」か「削除」
- todo へのタスク移動機能あり（API 経由で POST → shelf から削除）

## デプロイ・ビルド

- API: `mise run shelf:deploy`（Cloudflare Workers）
- Web: `mise run shelf:deploy:web`（Cloudflare Pages、Git連携なし・手動デプロイ）
- DB マイグレーション: `mise run shelf:deploy:migrate`（`apps/shelf/api/migrations/` に SQL 追加後に実行）
- iOS: `mise run shelf:build:ios`（xcodegen でプロジェクト生成 → Xcode で開く → Cmd+R で実機ビルド）
- `mise run shelf:test`（`apps/shelf/api` の vitest）は Tasks 系 9 件が main でも失敗する既知の状態（2026-07 時点）。テスト失敗を見たらまず main で再現するか切り分ける

## API

- 本番: https://todo-shelf-api.d0ne1s-todo.workers.dev
- Web: https://todo-shelf-web.pages.dev
- 認証: `Authorization: Bearer <API_SECRET>`
- Hono の `app.use("/xxx/*", auth)` は `/xxx`（ワイルドカードなしのベアパス）にマッチしない可能性がある。`GET /sections` のようなコレクション直下ルートを追加するときは `app.use("/xxx", auth)` も併記して認証漏れを防ぐ（index.ts の `/sections` 参照）
- D1 の prepared statement で `null` をバインドしても値がクリアされない。`column = NULL` と raw SQL で書くこと
- 日付は JST (UTC+9) で計算

## 通信遅延の調査手順

「時々 API 通信が数秒かかる」報告あり（2026-07 時点で原因未特定。正常時は shelf API・todo API とも 40〜180ms）。計測ログ仕込み済み:

- **クライアント側の記録**: 1秒超 or 失敗したリクエストを localStorage `slow-requests`（直近50件）と console `[slow-request]` に記録している（`apps/shelf/web/src/lib/api.ts`。todo への移動 POST も App.tsx で記録対象）。devtools console で `JSON.parse(localStorage.getItem("slow-requests"))` で確認
- **サーバー側の記録**: 全リクエストの所要時間を `{"method","path","status","ms"}` の JSON で console.log している（`apps/shelf/api/src/index.ts` のミドルウェア）。Workers Logs 有効化済み（wrangler.toml の `[observability]`）なので Cloudflare ダッシュボード → Workers & Pages → todo-shelf-api → Logs で過去分（無料プランで3日保持）を検索できる。リアルタイム監視は `npx wrangler tail todo-shelf-api`
- **切り分け**: localStorage に記録あり＋サーバーログの ms が小さい → ネットワーク経路。両方大きい → サーバー側（D1 レイテンシスパイク等）。localStorage に記録がないのに遅く感じた → フロント実装起因（下記）
- **フロントの既知の「遅く見える」要因**:
  - ~~「今日へ移動」は todo POST → shelf POST を直列 await し、完了までモーダルが開いたまま。エラーハンドリングもないため失敗するとモーダルが閉じず固まって見える（`App.tsx` handleMoveToToday）~~ → 2026-08-01 修正: 失敗時はリトライ付きトーストを表示。さらに (タスクID, 日付) から決定的に導出した UUID を todo POST の冪等キー `id` として送るため、連打・リトライ・数時間後の再操作でも同日移動は todo 側に1件しか登録されない（todo API 側の `INSERT OR IGNORE` 対応とセット）
  - ~~refreshKey 変更のたびに ProjectView が key ごと再マウントされ「読み込み中...」からフル再取得になる~~ → TanStack Query 導入（旧 cd97f92）で解消。起動時もキャッシュから即描画されるため、「開いたとき遅い」体感は今後ネットワーク/サーバー起因に絞られる
  - 詳細モーダルからの削除が DELETE 送信前に refreshKey を上げて再取得とレースする問題は旧 175cb45 で修正済み（現在は invalidateQueries ベース）

## シークレット・バインディング

### API（Cloudflare Workers）
- シークレット（`wrangler secret put` で管理）:
  - `API_SECRET` - API 認証トークン
  - `TODO_APP_API_SECRET` - todo API 連携用トークン
- バインディング:
  - D1: `DB` → `todo-shelf-db`
  - R2: `ATTACHMENTS` → `todo-shelf-attachments`
- vars（wrangler.toml で管理）:
  - `TODO_APP_API_URL`

### Web（Cloudflare Pages）
- 必要な変数は `apps/shelf/web/.env.example`（追跡対象）を参照。ローカル用は `.env`、本番用は `.env.production`（どちらも gitignore 対象）
- **本番の値は手元の `vite build` で bundle に焼き込まれる**。Pages は Git 連携なしの手動デプロイ（`mise run shelf:deploy:web`）なので、**Pages ダッシュボードの環境変数は手元のビルドには注入されない**。`.env.production` を移し忘れると localhost 向けの本番サイトを publish してしまうため、`vite.config.ts` が production ビルド時に必須変数の未設定・localhost を検出して落とす
- そのため `npm run build`（production モード）は `.env.production` が無い環境では意図的に失敗する。ビルドが通るかだけ確認したいときは `.env.example` をコピーしてダミー値を入れる

### iOS
- xcodegen で `apps/shelf/ios/project.yml` からプロジェクト生成
- API URL は `APIClient.swift` にハードコード。シークレットは `apps/shelf/ios/.env` の `API_SECRET` から `scripts/generate-projects.sh` が `Sources/Secrets.swift` を生成する（todo と同じ仕組み。`Secrets.swift` は gitignore 対象）
- `DEVELOPMENT_TEAM` も `.env` から project.yml のプレースホルダーに差し込まれる

## プロジェクト名のハードコード

- コード内で `p.name === "Shelf"`, `"Backlog"`, `"Archive"` などプロジェクト名の完全一致で表示制御している箇所がある（Web: App.tsx, Fab.tsx / iOS: ContentView.swift）
- プロジェクト名を変更する場合、コード変更 → デプロイ → DB リネームの順で行うか、同時に反映すること

## Web のキャッシュ層（TanStack Query）

- **放置後の最新化は focus イベント監視＋60秒ポーリングの2段構え**（main.tsx）。v5 の focusManager は `visibilitychange` しか監視せず「ウィンドウが見えたまま別アプリから戻る」「スリープ復帰」を拾えないため、`focusManager.setEventListener` で `focus` イベントも追加登録している。**`handleFocus` は必ず引数なしで呼ぶ**（`handleFocus(true)` だと `setFocused` 経由になり値が変化した初回しか発火しない）。`refetchInterval: 60_000` は visible なタブでのみ動き、フォーカスイベントが発火しないケースのセーフティネット
- 取得・キャッシュは useQuery（localStorage persister で永続化、キー: `["projects"]` `["sections"]` `["upcoming"]` `["tasks", projectId]` `["archived"]`）、D&D・楽観的更新は ProjectView の local state、というハイブリッド構成。書き込みは **API 成功を await した後に** `invalidateQueries` で収束させる（先に invalidate すると書き込み前の値で refetch されるレースになる）
- ProjectView は query data → local state を useEffect で同期している。ドラッグ中（`dragTypeRef` 非 null）は同期をスキップして楽観的状態の上書きを防ぐ
- ESLint の `react-hooks/set-state-in-effect` が「effect 内の同期 setState」を error にする。新しい view では local state を持たず query data 直参照 ＋ `setQueryData` を優先する（ArchiveView 方式）。local state が必要な場合は `useState(() => queryData ?? [])` で初期値をキャッシュから席込み＋親で `key={id}` remount にするとフラッシュも防げる

## dnd-kit

- 複数コンテナ間 D&D では `closestCenter` ではなくカスタム collision detection を使い、タスク要素を droppable ゾーンより優先する
- 同一コンテナ内の並べ替えは `arrayMove` を使う（手動 splice はドラッグ方向でズレる）

## iOS

- SwiftUI 標準の `.onDrag`/`.onDrop` はセクション間 D&D に不向き（アニメーション制御の限界、スクロールとの競合）。また SwiftUI の `LongPressGesture.sequenced(before: DragGesture)` を行に付ける方式は、行上で始まったタッチをジェスチャーが主張して ScrollView のスクロールをブロックする（タスクが画面を埋めるとスクロール不能になる）。現行実装は **UIScrollView に `UILongPressGestureRecognizer` を1本付けて D&D を駆動**（`TaskDragRecognizer.swift`）+ `PreferenceKey` で frame 収集 + オートスクロール（`DragController.swift`）という構成。UIKit の長押しはスクロールのパンと failure requirement で自然に調停される（指が動けばスクロール、止まればドラッグ）。タッチ座標は "project" named coordinate space の view の background に置いた anchor UIView 経由で変換し、`shouldReceive` でタスク行の上のタッチだけ受ける（セクションヘッダーの contextMenu と競合させないため）
- カスタムジェスチャーを付ける View は `Button` を避けて `HStack + .onTapGesture` にする。`Button` + 外側 gesture は `.simultaneousGesture`（両発火）/ `.gesture`（Button 常勝）/ `.highPriorityGesture`（外側常勝）のどれも破綻する
- ジェスチャーに紐づく一時状態は `@GestureState` を使うとキャンセル時も自動リセットされる。手動管理の `@State` フラグは `.onEnded` が呼ばれない経路で汚染されるリスクあり
- 新規 Swift ファイルを追加したら `xcodegen generate` を再実行してからビルドする（自動では Xcode プロジェクトに含まれない）
- `xcodegen generate` 直後はハーネス側 SourceKit のキャッシュが古いまま「Cannot find type 'XX'」「Cannot find 'Theme' in scope」等を大量に出すことがあるが、実際の `xcodebuild` は通る。診断ノイズに振り回されて書き換えに走らず、`mise run shelf:build:ios` か `xcodebuild` で実ビルドを確認する
- プロジェクト内の `struct Task: Codable`（Models.swift）が Swift 標準の並行処理 `Task` を shadow する。非同期ブロックを起動する時は `Swift.Task { ... }` と修飾すること（素の `Task { ... }` は `Task(from: Decoder)` に解決されて "trailing closure passed to parameter of type 'any Decoder'" エラーになる）
