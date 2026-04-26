# iOS版オフライン対応（閲覧 + 追加 / 削除 / タスク名更新の同期キュー）

## 概要・やりたいこと

iOS 版 todo-shelf は現状すべての操作がネット必須で、機内モードや圏外では完全に空表示・操作不可になる。少なくとも閲覧はできるようにしたい。さらに、オフライン中の「追加・削除・タスク名更新」をローカル反映 → オンライン復帰時に自動同期する仕組みを入れて、電車や地下でもストレスなく使えるようにする。

## 前提・わかっていること

### スコープ（dig-lite 結論）

- **閲覧**: タスク本体 + セクション + プロジェクト
  - コメント・添付ファイルは対象外（オフライン時は「読み込めません」表示）
- **書き込み**: 追加 / 削除 / タスク名更新 の3つ
- **対象外**: 並び替え、コメント追加・編集、添付、due_date 変更、セクション/プロジェクト間移動、プロジェクト/セクションの作成・編集

### 設計方針

- **キャッシュ保存先**: `Documents/cache.json`（既存 `Codable` モデルをそのまま JSON シリアライズ）
- **同期キュー保存先**: `Documents/queue.json`
  - 操作種別: `create` / `delete` / `update_title`
  - temp-ID で作成中のタスクへの編集/削除はキュー内のエントリを書き換えで吸収（ネットワークに送る前なら create を書き換え/取り消し、送信中なら本物 ID 解決後に再キュー）
- **ネットワーク検知**: `NWPathMonitor`
- **同期トリガー**: オンライン復帰時 + アプリフォアグラウンド復帰時（既存の自動リフェッチと同タイミング）
- **コンフリクト戦略**:
  - 削除: サーバー側で既に消えていたら 404 を握り潰す
  - タスク名更新: Last-Write-Wins、複数回更新は debounce してキュー内で1件にまとめる
- **UI**:
  - 上部に「オフライン · N件未同期」バナー（オンラインかつキューが空ならバナー非表示）
  - 保留中タスク行はクラウド斜線アイコンで区別

### 既存コードベースの把握

- `apps/ios/Sources/API/APIClient.swift` — actor、毎回ネット必須
- `apps/ios/Sources/ViewModels/ShelfViewModel.swift` — 既に `createTask` で temp-ID + リトライ toast の仕組みあり（同セッション内のみ、永続化なし）
- `apps/ios/Sources/Models/Models.swift` — `Project` / `Section` / `Task` がすべて `Codable`
- `apps/ios/project.yml` — 新規 Swift ファイル追加後は `xcodegen generate` 必須

## 実装計画

### Phase 1: ローカルキャッシュ層（閲覧オフライン対応） [AI🤖]

- [x] `Sources/Storage/LocalCache.swift` を新規作成
  - `actor` で `Documents/cache.json` の read/write を排他制御
  - 保存対象: `[Project]`, `[String: [Section]]`, `[String: [Task]]`
  - `load() -> CacheSnapshot?` / `save(_ snapshot: CacheSnapshot)`
  - JSON ファイル不在時は `nil` を返す
- [x] `ShelfViewModel.loadAll` を改修
  - 起動時: 先にキャッシュを `projects/sections/tasks` に流し込んで即表示 → 裏でネットフェッチ → 成功したら上書き + キャッシュ更新
  - フェッチ失敗時はキャッシュのまま維持、エラーメッセージのみ更新
- [x] `xcodegen generate` を実行してビルド確認

### Phase 2: ネットワーク監視 + オフラインバナー [AI🤖]

- [x] `Sources/Network/NetworkMonitor.swift` を新規作成
  - `@Observable` `@MainActor` クラス、`NWPathMonitor` で `isOnline` を公開
  - `ShelfApp.swift` で環境注入
- [x] `Sources/Views/OfflineBanner.swift` を新規作成
  - オフライン or 未同期件数 > 0 のとき表示
  - 文言例: 「オフライン · 3件未同期」「N件未同期」
- [x] `ContentView` 上部に `OfflineBanner` を配置
- [x] `xcodegen generate` を実行してビルド確認

### Phase 3: 同期キュー基盤 [AI🤖]

- [x] `Sources/Storage/SyncQueue.swift` を新規作成
  - `enum PendingOperation: Codable { case create(localId, projectId, sectionId, title); case delete(taskId); case updateTitle(taskId, title) }`
  - `actor SyncQueue`: `Documents/queue.json` に永続化、`enqueue` / `dequeue` / `peek` / `replace`
  - temp-ID から本物 ID への解決ヘルパー（create 完了後、後続のキュー内 delete/update_title の対象 ID を書き換え）
- [x] `Sources/Sync/SyncEngine.swift` を新規作成
  - `func sync()` で先頭から順次 `APIClient` を叩く
  - 各操作の成否によってキューから削除 or リトライ保留
  - 削除の 404 は成功扱い
  - 同期中フラグで多重実行防止
- [x] `ShelfApp.swift` でフォアグラウンド復帰 + `NetworkMonitor.isOnline` 切り替えを監視 → `SyncEngine.sync()` を呼ぶ
- [x] `xcodegen generate` を実行してビルド確認

### Phase 4: ViewModel をオフライン書き込み対応に改修 [AI🤖]

- [x] `createTask`: 既存の temp-ID 即時反映はそのまま、ネット失敗 or オフライン時は `SyncQueue.enqueue(.create(...))`
- [x] `deleteTask`: 即時にローカルから削除、ネット失敗 or オフライン時は `SyncQueue.enqueue(.delete(taskId))`
  - taskId が temp- で始まる（= まだサーバー未送信）場合はキュー内の create を取り消すだけ
- [x] `updateTask` のうち title 変更パス: 即時反映、ネット失敗 or オフライン時は `SyncQueue.enqueue(.updateTitle(...))` + 同 taskId の既存エントリは置換
- [x] キュー内に存在するタスクには `isPending: Bool` を計算プロパティ的に判定できるようにする（キュー保有 ID セットを ViewModel に公開）
- [x] `TaskRow` で `isPending` ならクラウド斜線アイコン表示
- [x] 並び替え/コメント/添付/due_date 変更/セクション移動はオフライン時に操作を無効化 or トーストで「オンライン時のみ」表示

### Phase 5: 同期完了フローの細部 [AI🤖]

- [x] create 完了時、サーバーが返した本物 ID で:
  - `tasks` 配列内の temp-ID を差し替え
  - 後続のキュー内 delete/update_title の対象 ID を `SyncQueue.resolveLocalId(temp, real)` で書き換え
- [x] 同期完了 → キャッシュも保存し直す
- [x] 同期エラー（ネット以外、例: 400/500）の扱いを決める: バナーに「同期エラー · タップで詳細」、または該当エントリをスキップしてユーザー通知

### 動作確認 [人間👨‍💻]

- [x] オンライン状態でアプリ起動 → 通常通り動作
- [x] アプリ起動後に機内モード ON → 一覧が表示され続ける（キャッシュから）
- [x] 機内モード ON でタスク追加 → 即時表示、保留中アイコン、上部バナーに「N件未同期」
- [x] 機内モード ON でタスク削除 → 即時消える、バナー件数++
- [x] 機内モード ON でタスク名変更 → 即時反映、バナー件数++（同タスク2回目以降は件数据え置き）
- [x] 機内モード OFF → バナー消える、サーバーに反映されることを Web 版 or curl で確認
- [x] 機内モード ON で追加 → そのままアプリ kill → 再起動（まだ機内）→ 保留タスクが残っている
- [x] 機内モード ON で「追加 → そのタスクを削除」→ オンライン復帰時にサーバーには何も飛ばない（キュー内で相殺）
- [x] 機内モード ON で「追加 → そのタスクの名前を変更」→ オンライン復帰時に正しい名前で1回だけ create される

## ログ
### 試したこと・わかったこと
- ビルド検証: `xcodegen generate` → `xcodebuild ... build` で Swift 6 strict concurrency 下も警告ゼロで成功
- アイコンは「クラウド斜線」案だったが、SF Symbols の `arrow.triangle.2.circlepath`（同期中アイコン）の方が「未同期＝サーバーに送られていない」のニュアンスを表現しやすかったので変更
- ネット失敗判定は `error is APIError` で分岐: APIError は HTTP 応答が返っている = サーバー到達済み、それ以外（URLError 等）はネット起因とみなしてキューに積む

### 方針変更
- **SyncEngine.swift を作らず ShelfViewModel.sync() に統合**
  - 理由: SyncEngine の中身が「キューを読んで APIClient を叩いてローカル状態（tasks 配列）を更新する」だけで、ViewModel への参照が前提になる。actor として独立させるよりメソッドにした方がシンプル、temp-ID 解決と tasks 配列差し替えが1か所で完結する
- **同期エラー時の「タップで詳細」UI は実装せず、シンプルな toast に変更**
  - 理由: 個人プロジェクトでサーバー側エラー（4xx/5xx）が頻発する想定がない。当該 op をスキップして toast「同期に失敗した操作がありました」のみ
- **`ShelfApp.swift` での環境注入はやめ、ContentView で `@State NetworkMonitor.shared` を直接参照**
  - 理由: 現状 NetworkMonitor を使うのは ContentView の onChange + sync トリガーのみ。シングルトン参照の方が薄い
