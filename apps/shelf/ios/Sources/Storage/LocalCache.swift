import Foundation

struct CacheSnapshot: Codable {
    var projects: [Project]
    var sections: [String: [Section]]
    var tasks: [String: [Task]]
}

actor LocalCache {
    static let shared = LocalCache()

    private let filename = "cache.json"

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent(filename)
    }

    func load() -> CacheSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(CacheSnapshot.self, from: data)
    }

    func save(_ snapshot: CacheSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
