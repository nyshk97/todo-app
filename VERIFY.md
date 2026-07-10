# 動作確認手順

## Web

### コード変更後のビルド検証

Web UI 変更後に TypeScript と Vite の本番ビルドが通ることを確認する。

```bash
cd apps/web
npm run build
```

- 末尾に `✓ built in` が出れば pass
- 型エラーや Vite build error が出たら fail

### UI 変更後のローカル表示確認

ローカルの Vite サーバーで対象画面を開き、変更した UI が意図した状態で表示されることを確認する。

```bash
cd apps/web
VITE_API_URL=https://todo-shelf-api.d0ne1s-todo.workers.dev npm run dev -- --host 127.0.0.1 --port 5173
```

- `http://127.0.0.1:5173/` をブラウザで開き、対象 UI を目視確認できれば pass
- API データが必要な確認では、データ作成や削除を伴わない操作に留める

### キャッシュ層（TanStack Query）の回帰確認

キャッシュまわり（クエリキー、invalidate、persister 設定）を変更したときに確認する。agent-browser で:

```bash
agent-browser --session verify open http://localhost:5174 && agent-browser --session verify wait --load networkidle
# 1. localStorage にキャッシュが永続化されているか
agent-browser --session verify eval 'JSON.parse(localStorage.getItem("todo-shelf-query-cache")).clientState.queries.map(q => q.queryKey)'
# 2. API を遮断してリロードしてもキャッシュから描画されるか
agent-browser --session verify network route "http://localhost:8787/**" --abort
agent-browser --session verify open http://localhost:5174 && agent-browser --session verify wait 1500 && agent-browser --session verify screenshot
```

- 1 で `["projects"], ["sections"], ["upcoming"], ["tasks", <projectId>]` が出れば pass
- 2 のスクリーンショットでタスク一覧が表示されていれば pass（「読み込み中...」やエラー表示なら fail）
- 変更操作（追加・削除・更新）の後は `network requests --type xhr,fetch` で該当クエリの refetch（invalidate）が飛んでいることを確認する

## iOS

### コード変更後のビルド検証

Xcode を開かずに署名なしでシミュレータ向けビルドが通ることを確認する。新ファイル追加時は事前に `xcodegen generate` を実行すること。

```bash
cd apps/ios
xcodegen generate
xcodebuild -project Shelf.xcodeproj -scheme Shelf \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

- 末尾が `** BUILD SUCCEEDED **` なら pass
- 警告抽出: `... 2>&1 | grep -E "(warning:|error:)" | grep -v AppIntents.framework`
- `AppIntents.framework` 関連 warning は AppIntents 未使用のため無視

### オフライン回帰確認

一度オンラインで読み込んで cache を作った後、機内モードで一覧が表示されること、タスク追加・削除・タイトル更新が即時反映され未同期表示になること、オンライン復帰後に同期されることを確認する。コメント/添付/due date/移動/並び替え/プロジェクト・セクション操作はオフライン中に操作できないことを確認する。
