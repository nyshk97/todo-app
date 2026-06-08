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
