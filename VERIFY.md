# 動作確認手順

このリポジトリは todo（今日やるタスク）と shelf（あとでやるタスク）の 2 プロダクトを含む。
変更したプロダクトの手順だけを選んで実行する。

> **次回デプロイ時の申し送り（2026-08-01 のモノレポ統合）**
> package-lock.json をフル再生成したため、todo 7件 / shelf 21件の依存が semver 範囲内で上がっている
> （wrangler 4.79→4.118、react 19.2.5→19.2.8、vite 8.0.8→8.2.0 等）。
> ローカルのテスト・ビルド・dry-run は全て通っているが、**本番デプロイ後に下記の smoke を必ず実行**すること。
> 一度実施したらこの申し送りは削除してよい。

---

# iOS 実機での確認（todo / shelf 共通）

「ビルド → インストール → 起動 → プロセス生存」までは CLI で完結できる。
Xcode を開いて Cmd+R する必要はない。画面の目視が要る部分だけ人に依頼する。

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
# Model 列にスペースが入るので列番号では取れない。UDID の形で抜く
DEV=$(xcrun devicectl list devices | grep "available (paired)" \
  | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1)

cd apps/todo/ios          # shelf は apps/shelf/ios
PROJ=TodoApp; BUNDLE=com.d0ne1s.todoapp    # shelf は PROJ=Shelf; BUNDLE=com.d0ne1s.shelf

# 1. 実機向けビルド（署名・プロビジョニングの解決までここで確認できる）
xcodebuild -project "$PROJ.xcodeproj" -scheme "$PROJ" -destination "id=$DEV" -configuration Debug build

# 2. install → launch
APP=$(xcodebuild -project "$PROJ.xcodeproj" -scheme "$PROJ" -destination "id=$DEV" -configuration Debug \
  -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2}' | head -1)/$PROJ.app
xcrun devicectl device install app --device "$DEV" "$APP"
xcrun devicectl device process launch --device "$DEV" --terminate-existing "$BUNDLE"

# 3. 10秒ほど置いて同じ pid で生きているか（クラッシュ再起動の検出）
sleep 10 && xcrun devicectl device info processes --device "$DEV" | grep "$PROJ"
```

- `BUILD SUCCEEDED` ＋ install 成功 ＋ 10秒後も同じ pid → 起動まわりは pass
- TodoApp では `TodoWidgetExtension` のプロセスも出ればウィジェットが読み込まれている
- **端末がロックされていると失敗するが、症状が段階によって違う**（どれも実機側の異常ではないので、まず解除してリトライする）
  - ビルド: `Timed out waiting for all destinations ... may need to be unlocked`
  - install: **ロック中でも成功する**
  - launch: `FBSOpenApplicationServiceErrorDomain error 1` / `CoreDeviceError error 10002`
  - 作業中に再ロックされることがあるので、install が通ったのに launch だけ落ちたらまずロックを疑う
- 実機ビルドはシミュレータビルドと違って**署名・プロビジョニングまで解決する**ので、`.xcodeproj` の再生成やパス変更の後はこれを通しておくと Xcode で詰まらない
- 以下は画面を見ないと判定できないのでユーザーに依頼する: 一覧の表示内容、タスクの追加・完了、ウィジェットの表示更新、shelf の「今日へ移動」が todo 側に反映されるか

---

# todo（`apps/todo/`）

## API

- テスト実行: `cd apps/todo/api && npm test`

### API deploy 後の本番 smoke

`apps/todo/ios/.env` の `API_SECRET` を使う（`.dev.vars` は production secret と一致しないことがある）。
**読み取り（正常系＋D1）と認可の両方**を確認する。認可だけでは Worker 起動しか分からず、D1 の疎通を見逃す。

```bash
API=https://todo-app-api.d0ne1s-todo.workers.dev
SECRET=$(grep '^API_SECRET=' apps/todo/ios/.env | cut -d= -f2-)

# 1. 正常系＋D1 読み取り: 200 で配列が返る
#    日付は未来日にする。今日を指定すると carry-over の INSERT が走り読み取り専用でなくなる
#    （todos.ts の GET は date === today のとき未完了タスクを自動繰り越しする）
curl -s -o /tmp/todo.json -w '%{http_code}\n' -H "Authorization: Bearer $SECRET" "$API/todos?date=2099-01-01"
jq -e '.todos | type == "array"' /tmp/todo.json   # 配列が返れば D1 まで到達している（空配列でよい）

# 2. 認可: secret なしは 401
curl -s -o /dev/null -w '%{http_code}\n' "$API/todos?date=2099-01-01"

# 3. 未来日への POST は 403（DB に作成されないので副作用なし）
curl -s -o /dev/null -w '%{http_code}\n' -X POST -H "Authorization: Bearer $SECRET" \
  -H 'Content-Type: application/json' -d '{"title":"smoke","date":"2099-01-01"}' "$API/todos"
```

- 1 が `200` かつ `.todos` が配列 → Worker・認証・D1 すべて OK
- 2 が `401`、3 が `403` → 認可 OK
- **注意**: Claude Code の Bash から `curl` だけ DNS を引けないことがある。その場合は
  `agent-browser` で開くか `! curl ...` でユーザーのターミナルに逃がす（グローバル CLAUDE.md 参照）

## iOS アプリ

- 実機にインストール: `mise run todo:build:ios` → Xcode で iPhone を選択して Cmd+R
- シミュレータ向けビルド検証 (CLI): `bash scripts/generate-projects.sh && xcodebuild -project apps/todo/ios/TodoApp.xcodeproj -scheme TodoApp -sdk iphonesimulator -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build`

## macOS アプリ

- 開発用のビルド＆起動: `mise run todo:build:mac`（未署名。配布物ではない）

### 署名まわりだけ確認する（notarize を飛ばす・1 分程度）

```bash
mise run todo:build:sign-only
```

- `==> 署名 OK（adhoc でない / Team VYDUR99LAM / timestamp あり / runtime / get-task-allow なし）` が出ること
- **`build/TodoMac.zip` が作られていないこと**（`ls build/`）。このモードは配布 ZIP を作らない。
  作ってしまうと未検証の成果物が後段（release）に拾われる

署名属性を自分の目で見るなら:

```bash
APP=build/derived/Build/Products/Release/TodoMac.app
codesign -dvv "$APP" 2>&1 | grep -E "Signature|TeamIdentifier|Timestamp|flags"
codesign -d --entitlements - "$APP"   # get-task-allow が出ないこと
```

### 成果物が中途半端に残らないことの確認

notarize は途中で落ちる工程が多いので、失敗しても `build/TodoMac.zip` を残さない作りになっている。
存在しないプロファイルを渡すと安全に再現できる:

```bash
NOTARY_PROFILE=nonexistent-profile-for-test bash scripts/build.sh; echo "exit=$?"
ls build/*.zip
```

`exit=1` で終わり、ZIP が 1 つも無いこと（提出用の `TodoMac-notarize.zip` も `trap` で消える）。

### Gatekeeper の確認（配布経路の模擬）

`brew` 経由で入るアプリには quarantine 属性が付く。属性を付けた状態で起動できるかが staple の効き目そのもの。
**常駐アプリなので、旧プロセスを終了して消えるのを待ってから差し替える**
（残っていると `open` しても既存プロセスが前面化されるだけで「起動できた」と誤認する）。

```bash
STAGE=$(mktemp -d) && ditto -x -k build/TodoMac.zip "$STAGE"
osascript -e 'tell application "TodoMac" to quit'
until ! pgrep -x TodoMac >/dev/null; do sleep 1; done
rm -rf /Applications/TodoMac.app && ditto "$STAGE/TodoMac.app" /Applications/TodoMac.app
xattr -w com.apple.quarantine "0081;$(printf %x $(date +%s));Safari;$(uuidgen)" /Applications/TodoMac.app
open /Applications/TodoMac.app && pgrep -x TodoMac
spctl --assess --type execute -vv /Applications/TodoMac.app   # source=Notarized Developer ID
```

Gatekeeper のダイアログが出ずに起動すれば pass。**確認後は属性を消して起動し直す**
（付いたままだと App Translocation で `/private/var/folders/.../AppTranslocation/` から実行され続ける）:

```bash
osascript -e 'tell application "TodoMac" to quit'
until ! pgrep -x TodoMac >/dev/null; do sleep 1; done
xattr -d com.apple.quarantine /Applications/TodoMac.app
open /Applications/TodoMac.app
ps -o pid,comm -p "$(pgrep -x TodoMac | head -1)"   # /Applications/... から動いていること
```

最後にメニューバーから開いてタスクが取得できる（サーバー同期が通る）ことを目視で確認する。

## リリース

- 配布用ビルド: `mise run todo:build`（署名 + notarize + staple + 配布 ZIP の検証。数分かかる）
  - `status: Accepted` / `The staple and validate action worked!` /
    配布 ZIP を展開しての `spctl --assess` → `source=Notarized Developer ID` が全部出ること
- リリース作成: `mise run todo:release -- <version>`（**実行すると即公開される**）
  - notarize を commit/push より前に通す。失敗しても remote には何も反映されず、
    `git checkout apps/todo/macos/project.yml` で戻せる

**`xcrun notarytool history --keychain-profile nyshk97-notary` が通らないときは画面ロックを疑う**
（資格情報は data-protection keychain にあり、ロック中は「プロファイルが無い」ように見える）。
判定は `ioreg -n Root -d1 -a | plutil -extract IOConsoleLocked xml1 -o - -` が `<true/>` かどうか。

---

# shelf（`apps/shelf/`）

## API

- テスト実行: `cd apps/shelf/api && npm test`
- Tasks 系 9 件（＋ `Comments` suite）は main でも失敗する既知の状態。**失敗数ではなく失敗テスト名の集合**を main と比較して回帰を判定する

### API deploy 後の本番 smoke

`apps/shelf/web/.env.production` の `VITE_API_SECRET` を使う。読み取り専用なので副作用がない。

```bash
API=https://todo-shelf-api.d0ne1s-todo.workers.dev
SECRET=$(grep '^VITE_API_SECRET=' apps/shelf/web/.env.production | cut -d= -f2-)

# 1. 正常系＋D1 読み取り
curl -s -o /tmp/shelf-p.json -w '%{http_code}\n' -H "Authorization: Bearer $SECRET" "$API/projects"
jq -e 'length > 0' /tmp/shelf-p.json          # プロジェクトが1件以上returnされれば D1 まで到達
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $SECRET" "$API/sections"

# 2. 認可: secret なしは両方とも 401
curl -s -o /dev/null -w '%{http_code}\n' "$API/projects"
curl -s -o /dev/null -w '%{http_code}\n' "$API/sections"
```

- 1 がどちらも `200` かつ `/projects` が非空 → Worker・認証・D1 すべて OK
- 2 がどちらも `401` → 認可 OK。**`/sections` を省略しない**こと（ベアパスなので
  `app.use("/sections", auth)` の付け忘れは `/projects` だけ見ても検知できない）

## Web

### コード変更後のビルド検証

Web UI 変更後に TypeScript と Vite の本番ビルドが通ることを確認する。

```bash
cd apps/shelf/web
npm run build
```

- 末尾に `✓ built in` が出れば pass
- 型エラーや Vite build error が出たら fail
- **`.env.production` が無い / 雛形のままだと意図的に fail する**（`vite.config.ts` のガード）。
  ビルドが通るかだけ見たいときは `.env.example` をコピーして `VITE_API_SECRET` にダミー値を入れる

### Web deploy 後の本番 smoke

`mise run shelf:deploy:web` は**手元でビルドした bundle をそのまま publish する**（Pages ダッシュボードの
環境変数は注入されない）。デプロイ後は「本番 API を向いているか」を必ず確認する。

```bash
# 1. bundle にアプリ固有の localhost が焼き込まれていないこと（0 であること）
grep -o "localhost:8787\|localhost:8788" apps/shelf/web/dist/assets/*.js | wc -l
# 2. 本番 API のホスト名が入っていること
grep -o "todo-shelf-api\.[a-z0-9.-]*workers\.dev" apps/shelf/web/dist/assets/*.js | head -1

# 3. 公開サイトが本番 API に接続して一覧を描画すること
agent-browser --session verify open https://todo-shelf-web.pages.dev
agent-browser --session verify wait --load networkidle
# networkidle だけでは早すぎる。描画完了（「読み込み中...」の消滅）まで待つ
agent-browser --session verify wait --fn '!document.body.innerText.includes("読み込み中")'
agent-browser --session verify network requests --type xhr,fetch --status 2xx
agent-browser --session verify screenshot
```

- 1 が `0`、2 が本番ホスト → 焼き込み OK
- 3 で `todo-shelf-api...workers.dev` への fetch が `2xx` で、スクリーンショットにタスク一覧が出れば pass
  （エラー表示や localhost への失敗リクエストがあれば fail）
- **`wait --load networkidle` の直後に撮ると必ず「読み込み中...」になる**（fetch は飛んでいるが
  レスポンス反映前に networkidle が成立し、`network requests` に status もまだ出ない）。
  正常なデプロイを fail と誤判定するので、`wait --fn` を必ず挟む
- **React Router 由来の汎用文字列 `http://localhost` は bundle に1件残る**ので、
  「localhost がゼロ」ではなく**アプリ固有の `localhost:8787` / `localhost:8788` がゼロか**で判定する

### UI 変更後のローカル表示確認

ローカルの Vite サーバーで対象画面を開き、変更した UI が意図した状態で表示されることを確認する。

```bash
cd apps/shelf/web
VITE_API_URL=https://todo-shelf-api.d0ne1s-todo.workers.dev npm run dev -- --host 127.0.0.1 --port 5173
```

- `http://127.0.0.1:5173/` をブラウザで開き、対象 UI を目視確認できれば pass
- API データが必要な確認では、データ作成や削除を伴わない操作に留める

### D&D（dnd-kit）の回帰確認

D&D まわり（ProjectView のドラッグハンドラ、collision detection）を変更したときに確認する。
**「UI 上動いて見えるか」ではなく「永続化リクエストが飛んだか」を判定基準にする**（onDragOver の楽観的更新だけで見た目は成功するため）。

```bash
# ドラッグは eval で PointerEvent を合成する（dnd-kit の PointerSensor は合成イベントでも動く）。
# ⠿ ハンドルに pointerdown → 5px 超の pointermove を数回（各 80〜100ms 空ける）→ pointerup
agent-browser --session verify eval --stdin <<'EVALEOF'
(async () => {
  const spans = () => Array.from(document.querySelectorAll("span"));
  const titleSpan = spans().find((s) => s.textContent === "<ドラッグするタスク名>");
  const handle = Array.from(titleSpan.parentElement.children).find((c) => c.textContent === "⠿");
  const r = handle.getBoundingClientRect();
  const sx = r.x + r.width / 2, sy = r.y + r.height / 2;
  const tx = <ドロップ先x>, ty = <ドロップ先y>;  // 移動先セクションの「タスクを追加」ボタンの getBoundingClientRect() 等から取る
  const fire = (type, tgt, x, y) => tgt.dispatchEvent(new PointerEvent(type, {
    bubbles: true, cancelable: true, pointerId: 1, pointerType: "mouse",
    isPrimary: true, button: type === "pointermove" ? -1 : 0, buttons: 1, clientX: x, clientY: y }));
  const sleep = (ms) => new Promise((res) => setTimeout(res, ms));
  fire("pointerdown", handle, sx, sy);
  await sleep(50);
  for (let i = 1; i <= 6; i++) { fire("pointermove", document, sx + (tx-sx)*i/6, sy + (ty-sy)*i/6); await sleep(100); }
  fire("pointerup", document, tx, ty);
  await sleep(500);
  return "done";
})()
EVALEOF
# 永続化の裏取り: PATCH が飛んで 2xx か
agent-browser --session verify network requests --method PATCH
```

- 確認パターン: ①別タスクの真上へのドロップ ②**移動先セクション末尾の空き領域へのドロップ**（over が自分自身になる経路。2026-08-18 のバグはここだけ PATCH が飛ばなかった）③その場に置き直し（PATCH が飛ばないこと）
- ドロップ後にリロードして配置が維持されていれば pass。UI 上移動して見えても PATCH が無ければ fail
- 失敗パスは `network route "**/tasks/reorder" --abort` で遮断してからドラッグし、トースト表示＋元の位置への巻き戻しを確認する
- ローカル DB が空なら `npx wrangler d1 migrations apply todo-shelf-db --local` 後にプロジェクト・セクション・タスクを INSERT して使う

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

### フォーカス復帰時・定期の再取得（focusManager / refetchInterval）

フォーカス再取得やポーリング設定（main.tsx）を変更したときに確認する。API リクエストの発生時刻は Performance API で取る:

```bash
# focus イベントを合成して再取得が飛ぶか（staleTime 30秒を超えてから実行すること）
agent-browser --session verify eval 'window.dispatchEvent(new Event("focus")); "dispatched at " + Math.round(performance.now())'
agent-browser --session verify wait 2000
agent-browser --session verify eval 'JSON.stringify(performance.getEntriesByType("resource").filter(e => e.name.includes("localhost:8787")).map(e => Math.round(e.startTime)))'
```

- dispatch 時刻と同時刻の API リクエスト群が増えていれば pass
- **1回目だけでなく、2回目の focus 合成でも再取得されることを必ず確認する**（`handleFocus(true)` と boolean を渡す実装ミスだと初回しか効かず、1回の確認ではすり抜ける）
- 前回取得から 30 秒以内の focus では再取得されないこと（staleTime 尊重）も正常挙動
- refetchInterval のポーリングは resource entries が約 60 秒間隔で増えることで確認できる。interval タイマーは focus 再取得のたびにリセットされるので、focus 検証は「直前の取得時刻 + 30秒 〜 + 60秒」の窓を狙う

## iOS

### コード変更後のビルド検証

Xcode を開かずに署名なしでシミュレータ向けビルドが通ることを確認する。新ファイル追加時は事前にプロジェクト生成を実行すること。

```bash
bash scripts/generate-projects.sh   # 3プロジェクトまとめて生成（Secrets.swift も生成される）
cd apps/shelf/ios
xcodebuild -project Shelf.xcodeproj -scheme Shelf \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

- 末尾が `** BUILD SUCCEEDED **` なら pass
- 警告抽出: `... 2>&1 | grep -E "(warning:|error:)" | grep -v AppIntents.framework`
- `AppIntents.framework` 関連 warning は AppIntents 未使用のため無視
- `xcode-select` が CommandLineTools を向いていて `requires Xcode` エラーが出る場合は `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` を付ける

### シミュレータでの起動・UI 確認

UI 変更後、実機ビルドを依頼する前にシミュレータで起動と画面表示を確認する。

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
UDID=$(xcrun simctl list devices available | grep "iPhone 17 (" | grep -oE '[0-9A-F-]{36}')
xcrun simctl boot $UDID; xcrun simctl bootstatus $UDID -b
xcrun simctl install $UDID ~/Library/Developer/Xcode/DerivedData/Shelf-*/Build/Products/Debug-iphonesimulator/Shelf.app
xcrun simctl launch $UDID com.d0ne1s.shelf
sleep 4 && xcrun simctl io $UDID screenshot /tmp/shelf.png  # 起動画面を目視
```

- スクリーンショットにタスク一覧が表示されていれば pass（クラッシュ・空画面なら fail）
- ログを見たい場合は `launch` を `xcrun simctl launch --console-pty $UDID com.d0ne1s.shelf > app.log 2>&1 &` に置き換える
- **注意**: シミュレータのアプリも本番 API に接続する。検証操作はデータ変更を伴わないものに留める（タップで詳細を開く、同位置ドロップ等）
- タッチ合成が必要なジェスチャー検証はグローバル CLAUDE.md の「iOS Simulator へのタッチ合成」を参照

### オフライン回帰確認

一度オンラインで読み込んで cache を作った後、機内モードで一覧が表示されること、タスク追加・削除・タイトル更新が即時反映され未同期表示になること、オンライン復帰後に同期されることを確認する。コメント/添付/due date/移動/並び替え/プロジェクト・セクション操作はオフライン中に操作できないことを確認する。
