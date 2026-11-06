import Foundation
import LinkPresentation
import UniformTypeIdentifiers

// 共有シートから受け取ったものを「タイトルの初期値」と「URL」に分ける
// shelf の ShareExtension もこのファイルをビルドに入れている（apps/shelf/ios/project.yml）
struct SharedContent {
    var title: String
    var url: URL?

    @MainActor
    static func load(from items: [NSExtensionItem]) async -> SharedContent {
        var url: URL?
        var texts: [String] = []
        for item in items {
            if let text = item.attributedTitle?.string { texts.append(text) }
            if let text = item.attributedContentText?.string { texts.append(text) }
            for provider in item.attachments ?? [] {
                if url == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let loaded = await loadObject(URL.self, from: provider), !loaded.isFileURL {
                    url = loaded
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                          let text = await loadObject(String.self, from: provider) {
                    texts.append(text)
                }
            }
        }

        // テキストにだけ URL が入っている共有もある。URL はタイトルから外して url に寄せる（2 つ目以降の URL はタイトルに残す）
        var cleaned: [String] = []
        for text in texts {
            var rest = text
            for link in links(in: text) {
                if url == nil { url = link.url }
                if link.url == url { rest = rest.replacingOccurrences(of: link.text, with: "") }
            }
            let trimmed = rest.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !cleaned.contains(trimmed) { cleaned.append(trimmed) }
        }

        var title = cleaned.first ?? ""
        // X などは URL しか渡してこない。ページのタイトルを取りに行って初期値にする
        if title.isEmpty, let url {
            title = await fetchTitle(of: url) ?? ""
        }
        return SharedContent(title: title, url: url)
    }

    @MainActor
    private static func loadObject<T: _ObjectiveCBridgeable>(_ type: T.Type, from provider: NSItemProvider) async -> T?
    where T._ObjectiveCType: NSItemProviderReading, T: Sendable {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: type) { object, _ in
                continuation.resume(returning: object)
            }
        }
    }

    private static func links(in text: String) -> [(text: String, url: URL)] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap { match in
            guard let url = match.url, let r = Range(match.range, in: text),
                  url.scheme == "http" || url.scheme == "https" else { return nil }
            return (String(text[r]), url)
        }
    }

    @MainActor
    private static func fetchTitle(of url: URL) async -> String? {
        let provider = LPMetadataProvider()
        provider.timeout = 5
        return await withCheckedContinuation { continuation in
            provider.startFetchingMetadata(for: url) { metadata, _ in
                let title = metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: title?.isEmpty == false ? title : nil)
            }
        }
    }
}
