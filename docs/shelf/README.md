# docs/shelf

旧 `nyshk97/todo-shelf` リポジトリ由来のドキュメント。2026-08-01 のモノレポ統合時に
`docs/plans/` とのファイル名衝突（`2026-04-26-ios-offline-support.md`）を避けるため丸ごと隔離した。

**今後の plan は `docs/plans/` に書く。** ここは統合前の記録として残している。

## 読むときの注意

- **パス表記は統合前のもの**。`apps/api/` → `apps/shelf/api/`、`apps/ios/` → `apps/shelf/ios/`、
  `apps/web/` → `apps/shelf/web/`、`packages/shared/` → `packages/shelf-shared/` と読み替える
- **コミット SHA は現在のリポジトリに存在しない**。shelf の履歴は `git filter-repo` で
  パスを書き換えたため SHA が振り直されている。`cd97f92` のような旧 SHA は
  `migration-commit-map.txt`（`旧SHA 新SHA` の2列、55件）で引く

```bash
grep '^cd97f92' docs/shelf/migration-commit-map.txt
```
