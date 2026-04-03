import Foundation

actor APIClient {
    static let shared = APIClient()

    private let baseURL = "https://todo-app-api.d0ne1s-todo.workers.dev"
    private let secret = Secrets.apiSecret

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    private func request(_ path: String, method: String = "GET", body: Encodable? = nil) async throws -> Data {
        var url = URL(string: "\(baseURL)\(path)")!
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")

        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let http = response as? HTTPURLResponse
            throw APIError.httpError(statusCode: http?.statusCode ?? 0)
        }
        return data
    }

    func fetchTodos(date: String? = nil) async throws -> TodosResponse {
        var path = "/todos"
        if let date {
            path += "?date=\(date)"
        }
        let data = try await request(path)
        return try decoder.decode(TodosResponse.self, from: data)
    }

    func createTodo(title: String) async throws -> Todo {
        let data = try await request("/todos", method: "POST", body: ["title": title])
        return try decoder.decode(Todo.self, from: data)
    }

    func updateTodo(id: String, completed: Bool? = nil, title: String? = nil) async throws -> Todo {
        var body: [String: AnyCodable] = [:]
        if let completed { body["completed"] = AnyCodable(completed) }
        if let title { body["title"] = AnyCodable(title) }
        let data = try await request("/todos/\(id)", method: "PATCH", body: body)
        return try decoder.decode(Todo.self, from: data)
    }

    func deleteTodo(id: String) async throws {
        _ = try await request("/todos/\(id)", method: "DELETE")
    }

    func reorderTodos(items: [(id: String, position: Int)]) async throws {
        let body = ReorderRequest(items: items.map { ReorderItem(id: $0.id, position: $0.position) })
        _ = try await request("/todos", method: "PATCH", body: body)
    }
}

enum APIError: LocalizedError {
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .httpError(let code):
            return "HTTP Error: \(code)"
        }
    }
}

// MARK: - Helpers

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let v = value as? Bool { try container.encode(v) }
        else if let v = value as? String { try container.encode(v) }
        else if let v = value as? Int { try container.encode(v) }
        else if let v = value as? Double { try container.encode(v) }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { value = v }
        else if let v = try? container.decode(Int.self) { value = v }
        else if let v = try? container.decode(String.self) { value = v }
        else { value = "" }
    }
}

struct ReorderRequest: Codable {
    let items: [ReorderItem]
}

struct ReorderItem: Codable {
    let id: String
    let position: Int
}
