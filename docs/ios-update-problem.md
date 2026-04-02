# iOS アプリの配布・更新問題

## 前提

- 個人利用のアプリ。App Store に公開する予定はない
- 現在は Xcode から USB 接続で iPhone に直接インストールしている（Personal Team 署名）

## 現状の問題

- Personal Team 署名は **7 日間** で期限切れ → 毎週ビルドし直す必要がある
- Mac と iPhone を USB で繋いで Xcode からビルドする手間が毎回発生する

## 配布方法の選択肢

### 1. 現状維持（Xcode 直接インストール）

- 有効期間: **7 日**
- コスト: 無料
- 手間: 毎週 Mac + iPhone + USB で再ビルド
- 備考: 今やっている方法

### 2. TestFlight（Apple Developer Program 必要）

- 有効期間: **90 日**
- コスト: 年 $99（Apple Developer Program）
- 手間: 3 ヶ月ごとに Archive → アップロード → TestFlight から再インストール
- 備考: 審査不要（内部テスター枠）。ただし期限切れの管理は必要

### 3. Ad Hoc 配布（Apple Developer Program 必要）

- 有効期間: **1 年**（Provisioning Profile の期限）
- コスト: 年 $99
- 手間: 年 1 回プロファイル更新。OTA 配布サーバーを立てれば USB 不要にもできる
- 備考: UDID の事前登録が必要（個人利用なら問題なし）

### 4. Enterprise 配布

- 有効期間: 1 年
- コスト: 年 $299（Apple Developer Enterprise Program）
- 手間: -
- 備考: 個人では取得不可。組織向けなので選択肢外

### 5. PWA（ネイティブアプリをやめる）

- 有効期間: **無期限**
- コスト: 無料
- 手間: Web アプリとして再実装が必要
- 備考: プッシュ通知・ウィジェットなどネイティブ機能は制限される。ホーム画面に追加で「アプリっぽく」使える

### 6. AltStore / Sideloady 等のサイドローディングツール

- 有効期間: **7 日**（自動で再署名してくれるものもある）
- コスト: 無料
- 手間: ツールのセットアップ。AltStore は同じ Wi-Fi 上の Mac/PC が必要
- 備考: Apple の規約的にグレー。iOS 17.4+ (EU) では代替マーケットプレイスの道もあるが日本は対象外

### 7. 自動化で現状の手間を減らす

- 有効期間: 7 日（変わらない）
- コスト: 無料
- 手間: 初回のスクリプト構築のみ
- 備考: `xcodebuild` + `ios-deploy` 等で USB 接続時に自動ビルド＆インストールするスクリプトを組む。期限は変わらないが手間は減る

## 比較まとめ

| 方法 | 有効期間 | 年間コスト | 運用の手間 | ネイティブ機能 |
|---|---|---|---|---|
| Xcode 直接（現状） | 7 日 | 無料 | 高（毎週） | 全て使える |
| TestFlight | 90 日 | $99 | 中（3 ヶ月ごと） | 全て使える |
| Ad Hoc | 1 年 | $99 | 低（年 1 回） | 全て使える |
| PWA | 無期限 | 無料 | 高（再実装） | 制限あり |
| サイドローディング | 7 日 | 無料 | 中 | 全て使える |
| 自動化スクリプト | 7 日 | 無料 | 中（毎週だが自動） | 全て使える |

## 検討ポイント

- PWA は却下（ネイティブ機能が必要）
- $99/年は許容範囲 → Ad Hoc が最もコスパが良い（年 1 回更新）
- $99 は 1 アカウントの料金。今後別のアプリを作ってもすべてカバーできる

## 調査結果

### ウィジェットは Ad Hoc で動くか？

**動く。** ただしセットアップに注意点がある:

- メインアプリとウィジェットで **別々の Provisioning Profile** が必要
  - メインアプリ: `com.d0ne1s.todoapp` 用のプロファイル
  - ウィジェット: `com.d0ne1s.todoapp.widget` 用のプロファイル
- 両方の App ID を Apple Developer Portal で明示的に登録する必要がある
- 署名に使う Distribution Certificate は同じものを使う
- App Groups を使っている場合は両方の App ID で有効化が必要

### OTA（Wi-Fi 経由）インストールはできるか？

**できる。** 方法は 2 つ:

**自前で配布する場合:**
1. HTTPS サーバーに .ipa と manifest.plist を置く
2. `itms-services://` スキームのリンクを Safari で開くとインストールされる
3. HTTPS 必須（Let's Encrypt で OK）、自己署名証明書は不可

**簡単にやるならサービスを使う:**
- **Diawi** — .ipa をアップロードするだけでインストール用リンクを生成。無料枠あり（リンクの有効期限は 24 時間）
- **Firebase App Distribution** — 無料。テスター管理や CI/CD 連携もできる。テスターは Firebase App Tester アプリのインストールが必要

個人利用なら Diawi が最も手軽。継続的に使うなら Firebase App Distribution が良い。

### Provisioning Profile 期限切れ時の挙動

- **起動時に検証される** → 期限切れ後は **アプリが起動しなくなる**（クラッシュではなく、開かない）
- 使用中に期限が来ても即落ちはしないが、次回起動時にアウト
- 期限切れ後の復旧手順:
  1. Apple Developer Portal で Provisioning Profile を再生成
  2. 新しいプロファイルでアプリを再ビルド
  3. iPhone に再インストール
- インストール済みアプリのプロファイルだけを差し替えることはできない

### Apple Developer Program の登録手続き

- **既存の Apple ID でそのまま登録できる**（2 ファクタ認証の有効化が必要）
- 個人登録の場合、**D-U-N-S 番号は不要**
- 本人確認: Apple Developer アプリで **身分証明書のスキャン + 顔認証** が求められる場合がある
- 承認まで: 自動認証が通れば **数時間以内**。手動レビューになると数日〜数週間
- 年 $99 で自動更新。キャンセル可能

## 方針

**Ad Hoc 配布に移行する。**

## やること

### 1. Apple Developer Program に登録する（手動） ✅ 承認待ち

- ~~developer.apple.com/programs/enroll にアクセス~~
- ~~Apple ID でサインイン（2 ファクタ認証を有効にしておく）~~
- ~~本人確認を完了して $99 を支払う~~
- 承認を待つ（最長 48 時間。2026-04-02 に申請済み）
- 承認されると Account ページに「Certificates, IDs, & Profiles」が出現する

### 2. Apple Developer Portal でセットアップする（手動）

- **App ID を 2 つ登録する**
  - `com.d0ne1s.todoapp`（メインアプリ）
  - `com.d0ne1s.todoapp.widget`（ウィジェット）
- **iPhone の UDID を登録する**
- **Ad Hoc 用 Distribution Certificate を作成する**
- **Ad Hoc 用 Provisioning Profile を 2 つ作成する**
  - メインアプリ用（`com.d0ne1s.todoapp`）
  - ウィジェット用（`com.d0ne1s.todoapp.widget`）

### 3. Xcode のビルド設定を Ad Hoc 署名に変更する

- project.yml の署名設定を更新（Team ID、Provisioning Profile 指定など）
- generate-projects.sh を必要に応じて更新

### 4. Ad Hoc ビルド & インストールする

- Xcode で Archive → Ad Hoc エクスポートで .ipa を生成
- iPhone にインストール（USB or OTA）
- ウィジェットが正常に動作するか確認

### 5. （任意）OTA インストール環境を整える

- Diawi 等のサービスを使えば USB 不要でインストールできる
- 必要になったタイミングで検討すれば OK

### 6. 年次更新のリマインダーを設定する

- Provisioning Profile の期限（1 年後）にリマインダーを設定
- 期限前にプロファイル再生成 → 再ビルド → 再インストール
