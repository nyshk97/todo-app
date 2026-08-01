# iOS セクション並び替え

## 概要・やりたいこと

iOS アプリでセクションの並び替えをできるようにする。Web 版では dnd-kit で対応済みだが、iOS では未実装。
専用の「セクション並び替え」シートを用意し、SwiftUI の `.onMove` で並び替える方式を採用する。

## 前提・わかっていること

- API エンドポイント `PATCH /projects/:id/sections/reorder` は既に存在
- ViewModel の `reorderSections(projectId:, sectionIds:)` も実装済み
- **UI 層の追加のみ**で完結する
- セクションヘッダーのコンテキストメニューから並び替えシートを開く
- 作成時の位置指定は不要（末尾追加のまま）

## 実装計画

### Phase 1: 並び替えシート作成 [AI🤖]

- [x] `SectionReorderSheet` ビューを作成（`apps/ios/Sources/Views/SectionReorderSheet.swift`）
  - プロジェクトのセクション一覧を `List` + `.onMove` で表示
  - 完了ボタンで `viewModel.reorderSections()` を呼ぶ
  - `EditMode` を `.active` に固定してドラッグハンドルを常時表示
- [x] `SectionView` のコンテキストメニューに「セクションを並び替え」を追加
- [x] `ProjectView` に並び替えシートの表示状態を管理する `@State` を追加し、`SectionView` からのトリガーを受け取る

### 動作確認 [人間👨‍💻]

- [ ] iOS シミュレータまたは実機でセクションヘッダーを長押し → 「セクションを並び替え」を選択
- [ ] シートが開き、セクション一覧がドラッグハンドル付きで表示される
- [ ] セクションをドラッグして並び替え → 完了 → 元の画面に反映されている
- [ ] アプリを再起動しても順序が保持されている

## ログ

### 試したこと・わかったこと
（実装中に随時追記）

### 方針変更
（実装中に随時追記）
