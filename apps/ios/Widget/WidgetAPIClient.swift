import Foundation

struct WidgetTodoResponse: Codable {
    let id: String
    let title: String
    let completed: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, completed
    }
}

struct WidgetTodosResponse: Codable {
    let todos: [WidgetTodoResponse]
    let date: String
    let editable: Bool
}

actor WidgetAPIClient {
    static let shared = WidgetAPIClient()

    private let baseURL = "https://todo-app-api.d0ne1s-todo.workers.dev"
    private let secret = "done1s-todo-claudeflare-secret-desu"

    func fetchTodos() async throws -> WidgetTodosResponse {
        var req = URLRequest(url: URL(string: "\(baseURL)/todos")!)
        req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(WidgetTodosResponse.self, from: data)
    }
}
