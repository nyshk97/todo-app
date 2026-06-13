# 動作確認手順

## API

- テスト実行: `cd apps/api && npm test`
- API deploy 後の本番 smoke: `apps/ios/.env` の `API_SECRET` を使い、未来日への `POST /todos` が `403` を返すことを確認する。future date は DB に作成されないため副作用がない。`.dev.vars` は production secret と一致しないことがある。

## iOS アプリ

- 実機にインストール: `mise run build:ios` → Xcode で iPhone を選択して Cmd+R
- シミュレータ向けビルド検証 (CLI): `bash scripts/generate-projects.sh && xcodebuild -project apps/ios/TodoApp.xcodeproj -scheme TodoApp -sdk iphonesimulator -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build`

## macOS アプリ

- ビルド＆起動: `mise run build:mac`

## リリース

- ビルド: `mise run build`
- リリース作成: `mise run release -- <version>`
