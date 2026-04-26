# 動作確認手順

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
