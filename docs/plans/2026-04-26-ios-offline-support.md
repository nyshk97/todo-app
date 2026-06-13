# iOS アプリのオフライン対応

## 概要・やりたいこと

iOS アプリは現在ローカルキャッシュを持たず、起動時やデータ取得時にネットワークが無いと何も表示できない（メモリ上の配列のみで永続化なし）。これを改善し、オフラインでも快適に使えるようにする。

**目標**:
- オフライン時でも過去に閲覧したデータは閲覧できる
- オフライン時でも今日のタスクに対して追加/編集/削除/並び替えができる
- オンライン復帰時に裏で自動同期され、ユーザーが意識せずに使える

## 前提・わかっていること

### 現状のアーキテクチャ
- iOS アプリは `@Observable` な `TodoViewModel` がメモリ上に `todos: [Todo]` を保持するのみ。永続化なし
- API は日付スコープ (`GET /todos?date=YYYY-MM-DD`)、認証は Bearer トークン
- ID はサーバー側で `crypto.randomUUID()` 生成
- サーバー側 `isEditable()` により編集可能なのは「今日と昨日」のみ
- サーバー側で「今日のタスク取得時に前日の未完了を自動繰り越し」する仕様
- Widget は独立した `WidgetAPIClient` で API を直接叩いている（App Group 未使用）
- iOS / macOS で `APIClient.swift` `TodoViewModel.swift` `Todo.swift` `Theme.swift` がほぼ完全重複

### 今回の決定事項（dig フェーズ）
- **スコープ**: 閲覧は全期間オフライン可能、書き込み（追加/編集/削除/並び替え）は **今日のタスクのみ** オフライン可能（過去日はサーバー `isEditable` 制約と整合させる）
- **ストレージ**: **SwiftData** を採用（iOS 17+ ネイティブ、Codable 親和性、スキーマ進化が容易）
- **競合解決**: 最終書き込み勝ち + シンプルなキュー再送。マージ等の高度な解決はやらない
- **自動繰り越し**: クライアント側では繰り越しロジックを実装しない。オンライン復帰時にサーバーから取得し直して反映する
- **Widget**: 当面は今までどおり API 直叩きのまま。SwiftData の App Group 共有は Phase 2 以降の検討事項

### 技術的な勘所
- 新規作成タスクはオフライン時に temp ID（クライアント生成 UUID）を持たせ、同期成功時にサーバー ID へ置換する
- 並び替えは position 値ベースなので、オフラインでも position 計算は可能
- macOS との共通化はあるが今回は対象外（iOS のみ）。同じ仕組みを将来 macOS にも展開できるよう、過度に iOS 固有の作りにはしない

## 実装計画

### 事前準備 [人間👨‍💻]
- [ ] 特になし（API キー等は既に `.env` に設定済み）

### Phase 1: 閲覧オフライン対応（読み取りキャッシュ） [AI🤖]
- [x] SwiftData モデル `CachedTodo` `CachedDate` を定義（`apps/ios/Sources/Models/CachedTodo.swift`）
- [x] `ModelContainer` をアプリ起動時にセットアップ（`apps/ios/Sources/TodoApp.swift`）
- [x] `TodoViewModel.loadTodos()` を改修
  - オンライン成功: API 取得 → SwiftData に upsert → ViewModel に反映
  - 失敗: SwiftData から該当日のキャッシュを読む。キャッシュ無しなら空配列
  - 各 CRUD 成功時にもキャッシュを upsert/delete/reorder
- [x] ネットワーク到達状況の監視を追加（`apps/ios/Sources/NetworkMonitor.swift`、`NWPathMonitor` ラッパー）
- [x] エラー表示の改善: オフライン時はエラーバナーではなくヘッダーに `wifi.slash` アイコン
- [x] ネット復帰時に自動再取得（ContentView の `.onChange(of: monitor.isOnline)`）
- [x] CLI ビルド検証 (`xcodebuild ... iphonesimulator`) で BUILD SUCCEEDED
- [x] 機内モード ON/OFF での閲覧確認（実機/シミュレータ目視）→ 人間動作確認 (2026-04-26 OK)

### Phase 1 完了後の確認 [人間👨‍💻]
- [ ] Phase 1 を実機で触ってみて、書き込みオフラインも本当に必要か再判断する。閲覧だけで十分そうなら Phase 2 はスキップして良い

### Phase 2: 書き込みオフライン対応（今日のタスクのみ） [AI🤖]
- [x] SwiftData モデル `PendingOperation` を定義（`apps/ios/Sources/Models/CachedTodo.swift`）
  - kind: create / update / delete / reorder（`PendingOperationKind` enum を文字列化して保存）
  - ペイロード: todoId, date, title, completed, reorderItemsJSON, createdAt, retryCount
- [x] オフライン時の各操作で SwiftData を即時更新 + `PendingOperation` を enqueue
  - create: `tmp_<UUID>` の temp ID で `CachedTodo` 作成
  - update (title / completed): `CachedTodo` を更新
  - delete: `CachedTodo` を即削除 + delete 操作をキュー（temp ID の場合は API 不要なのでキュー実行時にスキップ）
  - reorder: 同じ日付の既存 reorder を上書き（キュー肥大化を抑制）
- [x] 「今日以外の日付では書き込み不可」のガード（オフライン時は `editable = cached.editable && isToday`、キャッシュ無しは `editable = isToday`、各 CRUD でも `guard isToday` チェック）
- [x] `SyncEngine` を新規追加（`apps/ios/Sources/SyncEngine.swift`）
  - `loadTodos` 冒頭で `await SyncEngine.shared.sync()` を呼んでサーバ取得前にキューを掃き出す
  - create 成功時に temp ID → server ID 置換（`CachedTodo` 差し替え + 後続 PendingOperation の todoId 書き換え + reorder JSON 内の ID 文字列置換）
  - 失敗時は retryCount をインクリメントしてキューに残置（次回 sync で再試行）
  - サーバ取得は `loadTodos` が継続して行うため、SyncEngine 自体は drain のみ
- [x] アプリ起動時（`task` モディファイア） / フォアグラウンド復帰時（scenePhase）/ オンライン復帰時にも sync をキック
- [x] WidgetCenter リロードは同期成功後にも呼ぶ（SyncEngine 内）
- [x] CLI ビルド検証 (`xcodebuild ... iphonesimulator`) で BUILD SUCCEEDED
- [ ] 機内モードで CRUD/並び替え → オンライン復帰 → サーバー反映確認 → 人間動作確認

### Phase 2 完了後の確認 [人間👨‍💻]
- [ ] Widget もキャッシュ参照に切り替えるか判断（必要なら App Group + 共有 ModelContainer の Phase 3 を立てる）
- [ ] macOS アプリにも同じ仕組みを移植するか判断

### 動作確認 [人間👨‍💻]
- [ ] 実機（iPhone）で機内モード ON にして以下を確認
  - 過去に閲覧した日付のタスクが表示される
  - 今日のタスクで追加/編集/完了切替/削除/並び替えができる
  - 過去日では書き込み UI が無効化されている（or エラー表示）
  - 機内モード OFF にすると数秒以内にサーバーへ反映される
- [ ] Mac の Web/macOS アプリで同じタスクを編集 → iOS をオフラインで編集 → オンライン復帰した時に「最終書き込み勝ち」になっているか
- [ ] アプリを kill → 再起動した時もキャッシュとキューが生きていること

## ログ

### 試したこと・わかったこと
- 2026-04-26: Phase 1 実装完了。`xcodebuild -sdk iphonesimulator` でビルド成功（エラー・警告なし）
- `canAddTask` を `isToday && editable && !isOffline` に変更。Phase 1 では書き込みオフライン非対応なのでオフライン時は入力欄も隠す
- ContentView 側で `monitor.isOnline` の変化を監視し、false→true でも自動的に `loadTodos()` を呼ぶ実装にした
- 2026-04-26: 実機目視確認 OK（機内モードでの閲覧、ネット復帰時の自動再取得、kill 後のキャッシュ永続、入力欄非表示、日付ナビゲーション、オンライン時の既存機能の回帰なし）
- 2026-04-26: Phase 2 実装完了。`xcodebuild -sdk iphonesimulator` で BUILD SUCCEEDED
- temp ID は `tmp_<UUID>` 形式。create がキュー未送信のまま削除されたケースは SyncEngine 側で API 呼び出しスキップ
- reorder のキュー肥大化対策として、enqueue 時に同じ日付の既存 reorder op を削除して最新で上書き
- create が成功した時点で `CachedTodo` の temp ID を server ID に差し替え + 後続キュー内の todoId と reorder JSON の文字列も置換
- 2026-06-13: 追加改善。キャッシュを先に表示して API 待ちで空にならないようにし、オンライン判定中の通信失敗は今日の操作ならオフラインキューに積むよう変更
- 2026-06-13: API の `POST /todos` / reorder に任意の `date` を追加。オフライン作成・並び替えを翌日に同期しても元の日付へ反映されるようにした
- 2026-06-13: iOS ヘッダー下にオフライン/同期待ちバナーを追加。API テスト 30 件 pass、iOS シミュレータ Debug build pass
- 2026-06-13: レビュー指摘対応。オンライン reorder でも `dateString` を渡す、未来日を `isEditable=false` にする、reorder の対象日不一致を 409 にする、network error 判定を retryable `URLError` に限定
- 2026-06-13: レビュー指摘対応。未同期 temp タスクの update/delete/reorder はオンライン表示中でも API 直叩きせずキューへ寄せ、create+delete はキュー投入時に相殺。同期中 race でも削除済み temp を cache に復活させない
- 2026-06-13: 追加レビュー指摘対応。送信中 create 後に temp が削除済みなら作成済み server todo を即 delete し、失敗時は real ID の delete op を残す。空 reorder と 400/403/409 reorder は queue を詰まらせない
- 2026-06-13: 追加レビュー指摘対応。SyncEngine は stale snapshot を順に回さず、各 iteration で次の pending op を SwiftData から取り直す。create/update/delete の 400/403/404/409 も永久ブロックさせず、同期エラーをバナーに出す

### 方針変更
（実装中に随時追記）
