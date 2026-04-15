import Foundation

actor APIClient {
    static let shared = APIClient()

    private let baseURL = "https://todo-shelf-api.d0ne1s-todo.workers.dev"
    private let secret = Secrets.apiSecret

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    private func request(_ path: String, method: String = "GET", body: (any Encodable)? = nil) async throws -> Data {
        let url = URL(string: "\(baseURL)\(path)")!
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

    // MARK: - Projects

    func fetchProjects() async throws -> [Project] {
        let data = try await request("/projects")
        return try decoder.decode([Project].self, from: data)
    }

    func createProject(name: String) async throws -> Project {
        let data = try await request("/projects", method: "POST", body: ["name": name])
        return try decoder.decode(Project.self, from: data)
    }

    func updateProject(id: String, name: String? = nil, position: Int? = nil) async throws -> Project {
        var body: [String: AnyCodable] = [:]
        if let name { body["name"] = AnyCodable(name) }
        if let position { body["position"] = AnyCodable(position) }
        let data = try await request("/projects/\(id)", method: "PATCH", body: body)
        return try decoder.decode(Project.self, from: data)
    }

    func deleteProject(id: String) async throws {
        _ = try await request("/projects/\(id)", method: "DELETE")
    }

    // MARK: - Sections

    func fetchSections(projectId: String) async throws -> [Section] {
        let data = try await request("/projects/\(projectId)/sections")
        return try decoder.decode([Section].self, from: data)
    }

    func createSection(projectId: String, name: String) async throws -> Section {
        let data = try await request("/projects/\(projectId)/sections", method: "POST", body: ["name": name])
        return try decoder.decode(Section.self, from: data)
    }

    func updateSection(id: String, name: String? = nil, position: Int? = nil) async throws -> Section {
        var body: [String: AnyCodable] = [:]
        if let name { body["name"] = AnyCodable(name) }
        if let position { body["position"] = AnyCodable(position) }
        let data = try await request("/sections/\(id)", method: "PATCH", body: body)
        return try decoder.decode(Section.self, from: data)
    }

    func deleteSection(id: String) async throws {
        _ = try await request("/sections/\(id)", method: "DELETE")
    }

    func reorderSections(projectId: String, items: [(id: String, position: Int)]) async throws {
        let body = ReorderRequest(items: items.map { ReorderItem(id: $0.id, position: $0.position) })
        _ = try await request("/projects/\(projectId)/sections/reorder", method: "PATCH", body: body)
    }

    // MARK: - Tasks

    func fetchTasks(projectId: String) async throws -> [Task] {
        let data = try await request("/projects/\(projectId)/tasks")
        return try decoder.decode([Task].self, from: data)
    }

    func createTask(title: String, projectId: String, sectionId: String? = nil, dueDate: String? = nil) async throws -> Task {
        var body: [String: AnyCodable] = [
            "title": AnyCodable(title),
            "project_id": AnyCodable(projectId),
        ]
        if let sectionId { body["section_id"] = AnyCodable(sectionId) }
        if let dueDate { body["due_date"] = AnyCodable(dueDate) }
        let data = try await request("/tasks", method: "POST", body: body)
        return try decoder.decode(Task.self, from: data)
    }

    func updateTask(id: String, title: String? = nil, projectId: String? = nil, sectionId: String?? = nil, dueDate: String?? = nil, position: Int? = nil) async throws -> Task {
        var body: [String: AnyCodable] = [:]
        if let title { body["title"] = AnyCodable(title) }
        if let projectId { body["project_id"] = AnyCodable(projectId) }
        if let sectionId { body["section_id"] = sectionId.map { AnyCodable($0) } ?? AnyCodable.null }
        if let dueDate { body["due_date"] = dueDate.map { AnyCodable($0) } ?? AnyCodable.null }
        if let position { body["position"] = AnyCodable(position) }
        let data = try await request("/tasks/\(id)", method: "PATCH", body: body)
        return try decoder.decode(Task.self, from: data)
    }

    func deleteTask(id: String) async throws {
        _ = try await request("/tasks/\(id)", method: "DELETE")
    }

    func reorderTasks(items: [(id: String, position: Int)]) async throws {
        let body = ReorderRequest(items: items.map { ReorderItem(id: $0.id, position: $0.position) })
        _ = try await request("/tasks/reorder", method: "PATCH", body: body)
    }

    func fetchUpcomingTasks(days: Int = 3) async throws -> [UpcomingTask] {
        let data = try await request("/tasks/upcoming?days=\(days)")
        return try decoder.decode([UpcomingTask].self, from: data)
    }

    func moveTaskToToday(id: String, title: String) async throws {
        // 既存todo-appに直接POST
        let todoAppURL = "https://todo-app-api.d0ne1s-todo.workers.dev"
        let url = URL(string: "\(todoAppURL)/todos")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        let today = formatter.string(from: Date())

        req.httpBody = try JSONEncoder().encode(["title": title, "date": today])

        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let http = response as? HTTPURLResponse
            throw APIError.httpError(statusCode: http?.statusCode ?? 0)
        }

        // 成功したらShelfから削除
        try await deleteTask(id: id)
    }

    // MARK: - Comments

    func fetchComments(taskId: String) async throws -> [Comment] {
        let data = try await request("/tasks/\(taskId)/comments")
        return try decoder.decode([Comment].self, from: data)
    }

    func createComment(taskId: String, content: String) async throws -> Comment {
        let data = try await request("/tasks/\(taskId)/comments", method: "POST", body: ["content": content])
        return try decoder.decode(Comment.self, from: data)
    }

    func updateComment(id: String, content: String) async throws -> Comment {
        let data = try await request("/comments/\(id)", method: "PATCH", body: ["content": content])
        return try decoder.decode(Comment.self, from: data)
    }

    func deleteComment(id: String) async throws {
        _ = try await request("/comments/\(id)", method: "DELETE")
    }
}

// MARK: - Error

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

struct AnyCodable: Codable, Sendable {
    let value: any Sendable

    static let null = AnyCodable(NSNull())

    init(_ value: any Sendable) { self.value = value }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if value is NSNull { try container.encodeNil() }
        else if let v = value as? Bool { try container.encode(v) }
        else if let v = value as? String { try container.encode(v) }
        else if let v = value as? Int { try container.encode(v) }
        else if let v = value as? Double { try container.encode(v) }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { value = NSNull() }
        else if let v = try? container.decode(Bool.self) { value = v }
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
