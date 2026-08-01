# todo-shelf を todo-app リポジトリに統合（モノレポ化）

## 概要・やりたいこと

todo-app と todo-shelf は別リポジトリだが、連携が深い（shelf の web/iOS/api の3箇所から todo-app API を呼ぶ、todo-app 側も CORS で shelf-web を許可）。直近の冪等キー対応では同じ機能のために両リポジトリへペアのコミット（todo-app: 663ec38 / todo-shelf: c30a3d4）が必要だった。

1リポジトリに統合して以下を得る:

- API 契約の変更が1コミット/1PRでアトミックに完結する
- もう片方のアプリのコード・挙動を常に参照できる（Claude Code のセッションでも両方見える）
- 将来的にリポジトリ間の API 契約を TypeScript の型で共有できる土台を作る
- CLAUDE.md / VERIFY.md / docs の知見を一元化する

## 前提・わかっていること

- **ベースリポジトリは todo-app（nyshk97/todo-app）にする**。GitHub Releases と homebrew-tap の Cask URL（`github.com/nyshk97/todo-app/releases/download/...`）がそのまま生きるため、release.sh のリポジトリ指定・Cask の URL 変更が不要
- 両リポジトリとも CI（GitHub Actions）なし。デプロイは手動の mise タスクなので、パス変更の影響はローカルのスクリプト類に閉じる
- Cloudflare 側のリソース（Workers: todo-app-api / todo-shelf-api、D1、R2、Pages、secrets）はリポジトリ構成と無関係なので**一切変更不要**。デプロイ済みコードも変わらないため、統合に伴う再デプロイは不要
- npm workspaces のパッケージ名は衝突しない（`@todo-app/api`, `@todo-app/shared` / `todo-shelf-api`, `web`, `@todo-shelf/shared`）
- todo-shelf はローカル・リモートとも clean で同期済み（2026-08-01 時点で確認）
- todo-shelf は複数環境から push される運用（shelf の CLAUDE.md に明記）。統合前に他環境の未 push 作業がないことの確認が必要
- **履歴取り込みは `git filter-repo` によるパス書き換え → `git merge --allow-unrelated-histories` 方式**。`git subtree add` は検証の結果、prefix 変更前後のパスが自動追跡されず最終パスへの `git log --follow` が shelf 元コミットまで遡れないため不採用。filter-repo で一時 clone の履歴を最初から最終パス配置に書き換えてからマージすれば、`git log`（--follow 不要）で元コミットまで自然に辿れる
  - **filter-repo はコミット SHA を振り直す**（cd97f92 等の旧 SHA はマージ後リポジトリに存在しない）。旧 SHA → 新 SHA の対応は filter-repo が `.git/filter-repo/commit-map` に出力するので、これをリポジトリ内に保全し、履歴検証も commit-map ベースで行う
  - git-filter-repo は未インストール。単一ファイルの Python スクリプトなので GitHub から scratchpad に取得して `python3 git-filter-repo ...` で実行する（brew 経由のインストール不要）
  - 一時 clone はローカル filesystem から作るため **`git clone --no-local`** を使う（filter-repo 公式推奨。hardlink 共有による事故を防ぐ）
  - filter-repo が使えない場合のフォールバック: `git subtree add` で取り込み、「ファイル単位の履歴追跡（--follow）は shelf 由来ファイルでは効かない」制約を CLAUDE.md に明記する
- **ルートファイルの衝突は意図的なもの**: package.json / package-lock.json / .gitignore / .mise.toml / CLAUDE.md / VERIFY.md はマージ時にコンフリクト解決で統合する前提。同名衝突チェックはこの allowlist を除外した上で「重複ゼロ」を判定する
- **ファイル名衝突が既知で1件ある**: `docs/plans/2026-04-26-ios-offline-support.md` が両リポジトリに存在。shelf の docs は plans ごと丸ごと `docs/shelf/` 配下に隔離して衝突を回避する（今後の plan は `docs/plans/` に一本化）
- gitignore 対象の実ファイル（git では移動されない。同一マシンなので AI がコピー可能）:
  - todo-app 側（リポジトリ内移動に伴いコピー）: `apps/api/.dev.vars`, `apps/ios/.env`, `apps/macos/.env`（`Secrets.swift` 3つは generate-projects.sh で再生成可能）
  - todo-shelf 側（リポジトリ間コピー）: `apps/api/.dev.vars`, `apps/ios/Sources/Secrets.swift`, `apps/web/.env`, `apps/web/.env.production`
  - **shelf の `Secrets.swift` は生成スクリプトが存在しない**（現行 generate-projects.sh は todo 側専用）ため、実ファイルのコピーが必須
- **package-lock.json の再生成は Linux コンテナで行う**（グローバルルール準拠。CI の有無によらずプラットフォーム別 optional 依存の欠落を防ぐ）: `docker run --rm -v "$PWD:/app" -v /app/node_modules -w /app node:22-alpine sh -c "rm -f package-lock.json && npm install --package-lock-only"` → mac と Linux コンテナ両方で `npm ci --dry-run` 検証
- shelf の `mise run test` は Tasks 系 9 件が main でも失敗する既知の状態。統合後の検証は失敗**数**ではなく**失敗テスト名の集合**で比較する（統合前にベースラインを採取）
- 既存タグ `v*` は TodoMac のリリース。shelf にはリリースプロセスがないので当面タグ衝突はない。将来 shelf 系でリリースを作る場合はプレフィックス付きタグ（`shelf-v*` 等）を導入する
- 旧 todo-shelf にはルート README が存在しない → クローズ時は移行案内 README の**新規作成**になる

### 統合後のディレクトリ構造

```
apps/
  todo/
    api/      ← 旧 todo-app/apps/api
    ios/      ← 旧 todo-app/apps/ios
    macos/    ← 旧 todo-app/apps/macos
  shelf/
    api/      ← 旧 todo-shelf/apps/api
    ios/      ← 旧 todo-shelf/apps/ios
    web/      ← 旧 todo-shelf/apps/web
packages/
  todo-shared/    ← 旧 todo-app/packages/shared（@todo-app/shared）
  shelf-shared/   ← 旧 todo-shelf/packages/shared（@todo-shelf/shared）
scripts/          ← 両リポジトリの scripts を統合（衝突なしを確認済み: shelf 側は migrate-from-todoist.ts のみ）
docs/
  plans/          ← todo-app の plans ＋ 今後の plan 置き場
  shelf/          ← 旧 todo-shelf/docs 丸ごと（plans 含む。同名衝突回避のため隔離）
```

- ルート package.json の workspaces: `["apps/*/*", "packages/*"]`
- mise タスクは `todo:` / `shelf:` プレフィックスで統合（例: `todo:deploy`, `shelf:deploy:web`, `todo:build:mac`）
- CLAUDE.md はルートに統合（共通事項＋製品別セクション）。VERIFY.md（shelf 由来）もルートへ
- ルート README.md も新構造に合わせて更新する

## 実装計画

### 事前準備 [人間👨‍💻]
- [ ] 他の環境（別 Mac 等）に todo-shelf / todo-app の未 push 作業がないか確認する

### Phase 1: 履歴ごと取り込みと再配置 [AI🤖]
- [x] **取り込み元の固定**: 両リポジトリで `git fetch origin` を実行した上で、
  - todo-shelf: `git status --porcelain` が空（完全 clean）かつ `HEAD == origin/main` を確認し、取り込み元 SHA を本ファイルのログセクションに記録する
  - todo-app: tracked 変更がないこと（`git diff --quiet` && `git diff --cached --quiet`）、未追跡ファイルが本 plan ファイルだけであること、`HEAD == origin/main` を確認する（plan は次ステップのブランチ作成後にコミットするため、この時点では未追跡でよい。plan コミット以降のステップでは `git status --porcelain` 空を要求する）
- [x] 統合前ベースライン採取: 旧 todo-shelf で `npm test` を実行し、失敗テスト名の一覧を scratchpad に保存
- [x] todo-app に統合用ブランチ `merge-todo-shelf` を作成し、未追跡の本 plan ファイルをこのブランチで先にコミットする
- [x] **移動対象の同名衝突チェックを機械的に実行**: todo-app 側の移動後パス一覧と shelf 側の書き換え後パス一覧を突き合わせ、**allowlist（package.json / package-lock.json / .gitignore / .mise.toml / CLAUDE.md / VERIFY.md = 意図的なルート衝突）を除いて重複ゼロ**を確認（既知の docs/plans 衝突は `docs/shelf/` 隔離で解消済みのはず。それ以外が出たら方針を決めてから進む）
- [x] git-filter-repo スクリプトを GitHub から scratchpad に取得
- [x] todo-shelf を `git clone --no-local` で scratchpad に一時 clone（main が記録した SHA を指していることを確認）し、`git filter-repo --path-rename` で履歴全体を最終パスに書き換え:
  - `apps/api/` → `apps/shelf/api/`、`apps/ios/` → `apps/shelf/ios/`、`apps/web/` → `apps/shelf/web/`
  - `packages/shared/` → `packages/shelf-shared/`
  - `docs/` → `docs/shelf/`
  - `scripts/` はそのまま
  - ルートファイル（package.json / .mise.toml / CLAUDE.md / VERIFY.md / package-lock.json / .gitignore）はそのまま（マージ時に統合）
  - ※ --path-rename の適用順序（先勝ちルール）は実行前に `--dry-run` 等で確認する
- [x] filter-repo 実行後、一時 clone の `.git/filter-repo/commit-map`（旧 SHA → 新 SHA 対応表）を退避し、後のステップで `docs/shelf/migration-commit-map.txt` としてリポジトリにコミットする
- [x] todo-app 側を `git mv`: `apps/{api,ios,macos}` → `apps/todo/`、`packages/shared` → `packages/todo-shared`（通常の rename なので --follow で追跡可能）。**この再配置をコミットし、`git status --porcelain` が空であることを確認してから次へ進む**（未コミットのまま merge すると `Your local changes would be overwritten by merge` で失敗する）
- [x] 一時 clone を remote 追加 → fetch → `git merge --allow-unrelated-histories` で取り込み。ルートファイルのコンフリクトを統合方針どおり解決:
  - package.json: workspaces を `["apps/*/*", "packages/*"]` に
  - .gitignore: 両方の union
  - .mise.toml: `todo:` / `shelf:` プレフィックスでタスク統合
  - CLAUDE.md: 共通事項＋製品別セクションに再構成
  - VERIFY.md: shelf 版をベースにルートへ
  - package-lock.json: 両方削除（次ステップで再生成）
- [x] **履歴検証（commit-map ベース）**: ①commit-map から cd97f92 に対応する新 SHA を取得 ②新 SHA がマージ後リポジトリに存在すること（`git cat-file -e`）③`git log -- apps/shelf/api/src/index.ts` 等に新 SHA（または同一 commit subject）が出ること、を確認
- [x] **後片付け**: commit-map が `docs/shelf/migration-commit-map.txt` としてコミット済みであることを確認してから、一時 remote を `git remote remove` で削除 → scratchpad の一時 clone と filter-repo スクリプトを削除 → `git remote -v` が通常の origin だけになったことを確認
- [x] **Linux コンテナで package-lock.json を再生成**し、mac と Linux コンテナの両方で `npm ci --dry-run` が通ることを確認
- [x] lockfile 再生成に伴う lint プラグイン更新の検出: `npm run lint --workspaces --if-present` と `npm run typecheck --workspaces --if-present` を実行し、触っていないファイルで新たに落ちるものがないか確認する

### Phase 2: パス参照の修正 [AI🤖]
- [x] `scripts/generate-projects.sh` / `scripts/build.sh` / `scripts/release.sh` のパスを新構造に更新（release.sh のリポジトリ指定 `nyshk97/todo-app` と Cask URL は変更しない）
- [x] ルート README.md の旧パス記述（apps/api, apps/ios, apps/macos）を新構造に更新
- [x] shelf iOS の xcodegen 呼び出し（mise `shelf:build:ios`）を新パスに更新
- [x] 両 API / web / shared 内に相対パスやリポジトリルート前提の参照が残っていないか grep で総点検（tsconfig の paths、wrangler.toml、project.yml、テスト内のパス等）
- [x] gitignore 対象ファイルを旧パスからコピー:
  - todo 側: `apps/todo/api/.dev.vars`, `apps/todo/ios/.env`, `apps/todo/macos/.env`（Secrets.swift は generate-projects.sh で再生成）
  - shelf 側: `apps/shelf/api/.dev.vars`, `apps/shelf/ios/Sources/Secrets.swift`, `apps/shelf/web/.env`, `apps/shelf/web/.env.production`
- [x] **コピーした全ファイルを `git check-ignore` で無視対象であることを確認**（特に .env.production の誤コミット防止）。`git status` にも出ていないことを確認
- [x] CLAUDE.md の記述内パス（`apps/api/` 等）を新構造に合わせて書き換え
- [x] ~~（任意）generate-projects.sh を shelf iOS にも対応させ、Secrets.swift を .env から生成できるようにする~~ → 見送り。実ファイルコピーで動く状態を優先し、「shelf の Secrets.swift は手動管理」を CLAUDE.md に明記した

### Phase 3: 検証 [AI🤖]
- [x] `npm test --workspace @todo-app/api`: 全パス
- [x] `npm test --workspace todo-shelf-api`: 失敗テスト名の集合が Phase 1 で採取したベースラインと**完全一致**すること（数だけでなく名前で比較）
- [x] `apps/shelf/web` で `npm run build` が通ること
- [x] `npx wrangler deploy --dry-run` を両 API で実行しエラーがないこと
- [x] xcodegen で 3 つの Xcode プロジェクト（TodoApp / TodoMac / Shelf）が生成でき、iOS 2つは `xcodebuild -sdk iphonesimulator` が通ること
- [x] ~~`mise run todo:build:mac` で TodoMac がビルド・起動すること~~ → **起動は見送り**。`/Applications/TodoMac.app`（brew 版）がユーザー稼働中で、タスクが送る `osascript quit` が実行中インスタンスを落とすため。ビルド部分（`xcodebuild` + 成果物の Info.plist 確認）と `scripts/build.sh`（Release + zip）は実行して成功を確認済み。起動確認は「統合後の確認 [人間👨‍💻]」に委譲
- [x] release.sh は実行せず、パス参照のレビューのみ（次回リリース時に実地検証）

### Phase 4: マージ・push [AI🤖]
- [x] `merge-todo-shelf` を main にマージして push（fast-forward。`main` = `origin/main` = 639bdf5）

### 統合後の確認・移行 [人間👨‍💻]
- [ ] 他環境の clone を統合後の todo-app に切り替える（todo-shelf の clone は削除）
- [ ] iOS 実機ビルド: TodoApp / Shelf を新パスの Xcode プロジェクトから Cmd+R でインストールし直して動作確認
- [ ] TodoMac のホットキー・パネル表示を一通り確認（未署名ビルドのパスが変わると Accessibility 権限の再付与が必要になる可能性あり）

### Phase 5: 旧リポジトリのクローズ [AI🤖]（上の人間確認が完了してから）
- [ ] 旧 todo-shelf に移行案内 README を**新規作成**（移行先 nyshk97/todo-app と統合コミットを明記）して push
- [ ] `gh repo archive nyshk97/todo-shelf` でアーカイブ（read-only 化）
- [ ] （任意・後日）リポジトリ名を `todo-app` から中立な名前（例: `todo`）にリネームするか検討。GitHub はリネーム後も旧 URL（git remote・Release ダウンロード URL とも）をリダイレクトするので Cask はそのまま動くが、次回 release.sh 実行前にリポジトリ指定を新名称に更新するのが安全

## ログ
### 試したこと・わかったこと
- 2026-08-01: gitignore 対象の実ファイルを両リポジトリで棚卸し（前提セクションに反映）。git-filter-repo は未インストールだが python3 あり、単一スクリプト取得で実行可能
- 2026-08-01: 取り込み元 SHA を固定。todo-shelf `c30a3d49304503edf7afd87843fbad95bb0de4be`（HEAD == origin/main、porcelain 空）／todo-app `9d870642262be530aadfd0bb72b2b39cc3259ae5`（HEAD == origin/main、未追跡は本 plan のみ）
- 2026-08-01: filter-repo の `--path-rename` は指定した5つのプレフィックスが互いに素なので順序依存なし。`--dry-run` の `.git/filter-repo/fast-export.filtered` を parse して、書き換え後パスが `apps/shelf/` `packages/shelf-shared/` `docs/shelf/` `scripts/` ＋ルート6ファイルだけになることを事前確認した
- 2026-08-01: 履歴検証 pass。コミット数 99（旧 todo-app）+ 55（shelf）+ 3（plan / 再配置 / merge）= 157 で一致。todo 側の旧 SHA は不変（filter-repo をかけていないため）、shelf 側は `docs/shelf/migration-commit-map.txt` で対応が引ける。`git log -- apps/shelf/api/src/index.ts` が `--follow` なしで初出（2026-04-15）まで遡れることを確認
- 2026-08-01: shelf テストのベースライン採取。`Tests 9 failed | 11 passed | 4 skipped (24)`。失敗は `Comments`（suite）＋ `Tasks > {creates a task without section, creates a task with section, lists tasks for project, updates task with due_date, clears task due_date with null, moves task to different section (null), reorders tasks, returns upcoming tasks, deletes a task}`

### 方針変更
- 2026-08-01: 計画レビューを受けて改訂。①取り込みを subtree → filter-repo 方式に変更（--follow が subtree では効かないため）②docs/plans の同名衝突（2026-04-26-ios-offline-support.md）を docs/shelf/ 隔離で回避③ignored ファイルの移行リストを明示＋check-ignore 検証追加④lockfile 再生成を Linux コンテナ方式に修正⑤テスト比較を失敗名の集合比較に強化⑥README 更新・後始末手順を追加⑦archive を人間確認の後（Phase 5）に移動
- 2026-08-01: 計画レビュー2巡目を受けて改訂。①todo 側 git mv を merge 前にコミットするステップを明示（未コミットだと merge が失敗する再現確認あり）②Phase 1 冒頭に fetch・clean 確認・取り込み元 SHA 固定を追加③履歴検証を commit-map ベースに変更（filter-repo は SHA を振り直すため。commit-map は docs/shelf/migration-commit-map.txt として保全）④衝突チェックにルートファイルの allowlist を導入⑤lockfile 再生成後の lint / typecheck 確認を追加⑥一時 clone に --no-local を明記
- 2026-08-01: lockfile のフル再生成で `eslint-plugin-react-hooks` が 7.0.1 → 7.1.1 に上がり、shelf/web の lint エラーが 1 → 6 に増えた。増分5件はすべて**イベントハンドラ内**の `Date.now()` / `performance.now()` を `react-hooks/purity` が「during render」と誤検知したもので、統合とは無関係。`apps/shelf/web/package.json` で 7.0.1 に固定して lint 出力を統合前と完全一致（Toast.tsx の react-refresh 1件のみ＝統合前から失敗）に戻した。プラグイン更新への追随は別タスク
- 2026-08-01: `mise run todo:build:mac` の起動確認を見送り（Phase 3 の該当行に理由を記載）。TodoMac は brew 版がユーザー稼働中で、タスク内の `osascript quit` が実行中インスタンスを落とすため
- 2026-08-01: 計画に無い追加変更を2点入れた。①`.mise.toml` の `release` タスクを deprecated な `{{arg(...)}}` から `usage` 方式（`usage = 'arg "<version>"'` ＋ `$usage_version`）に移行（グローバルルール準拠。ファイルを全面書き換えするタイミングだったため）②`.gitignore` の union で `.env` / `.env.local` を shelf 由来の `.env*` に置換（`apps/shelf/web/.env.production` を確実に無視するため。追跡中の `.env*` が両リポジトリに無いことを確認済み）
- 2026-08-01: 計画レビュー3巡目を受けて改訂。①clean 確認を todo-app / todo-shelf で分離（todo-app は本 plan が未追跡のため tracked 変更なし＋未追跡は plan のみ、で判定。plan コミット以降は porcelain 空を要求）②merge・commit-map 保全後の後片付けステップを追加（一時 remote 削除・scratchpad の一時 clone / filter-repo スクリプト削除・`git remote -v` 確認）
