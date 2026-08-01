# docs の構成

| パス | 内容 |
|---|---|
| `docs/plans/` | 実装計画。**今後の plan はここに一本化する**（todo / shelf 共通） |
| `docs/shelf/` | 旧 `nyshk97/todo-shelf` リポジトリ由来のドキュメント。統合時にファイル名衝突を避けるため丸ごと隔離した |
| `docs/PLAN.md` `docs/REQUIREMENTS.md` | todo の初期設計時の記録（完了済み） |
| `docs/refactoring-candidates.md` | 現役。パスは統合後の構造に更新済み |

## 統合前のパス表記について

2026-08-01 に todo-app と todo-shelf をモノレポへ統合しました。
**統合より前に書かれたドキュメント（`docs/PLAN.md`、`docs/REQUIREMENTS.md`、
`docs/plans/2026-04-*`、`docs/shelf/` 配下）は当時のパスのまま**で、
その時点の記録として意図的に更新していません。読むときは以下で読み替えてください。

| 当時のパス | 現在のパス |
|---|---|
| `apps/api/`（todo の文脈） | `apps/todo/api/` |
| `apps/ios/`（todo の文脈） | `apps/todo/ios/` |
| `apps/macos/` | `apps/todo/macos/` |
| `packages/shared/`（todo の文脈） | `packages/todo-shared/` |
| `apps/api/`（`docs/shelf/` 配下） | `apps/shelf/api/` |
| `apps/ios/`（`docs/shelf/` 配下） | `apps/shelf/ios/` |
| `apps/web/` | `apps/shelf/web/` |
| `packages/shared/`（`docs/shelf/` 配下） | `packages/shelf-shared/` |

`docs/shelf/` 配下の相対パスはすべて shelf 側として読みます。

## 旧 SHA について

shelf の履歴は `git filter-repo` でパスを書き換えたため**コミット SHA が振り直されています**。
`docs/shelf/` 内のドキュメントが参照する SHA（`cd97f92` 等）は現在のリポジトリには存在しません。
対応表は `docs/shelf/migration-commit-map.txt`（`旧 SHA 新 SHA` の2列）を引いてください。
