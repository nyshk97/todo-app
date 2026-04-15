import Foundation

struct Project: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var position: Int
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, position
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct Section: Codable, Identifiable, Equatable {
    let id: String
    let projectId: String
    var name: String
    var position: Int
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, position
        case projectId = "project_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct Task: Codable, Identifiable, Equatable {
    let id: String
    var projectId: String
    var sectionId: String?
    var title: String
    var dueDate: String?
    var position: Int
    let commentCount: Int
    var archivedAt: String?
    let createdAt: String
    let updatedAt: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        projectId = try c.decode(String.self, forKey: .projectId)
        sectionId = try c.decodeIfPresent(String.self, forKey: .sectionId)
        title = try c.decode(String.self, forKey: .title)
        dueDate = try c.decodeIfPresent(String.self, forKey: .dueDate)
        position = try c.decode(Int.self, forKey: .position)
        commentCount = try c.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
        archivedAt = try c.decodeIfPresent(String.self, forKey: .archivedAt)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, position
        case projectId = "project_id"
        case sectionId = "section_id"
        case dueDate = "due_date"
        case commentCount = "comment_count"
        case archivedAt = "archived_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ArchivedTask: Codable, Identifiable, Equatable {
    let id: String
    var projectId: String
    var sectionId: String?
    var title: String
    var dueDate: String?
    var position: Int
    let commentCount: Int
    var archivedAt: String?
    let createdAt: String
    let updatedAt: String
    let projectName: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        projectId = try c.decode(String.self, forKey: .projectId)
        sectionId = try c.decodeIfPresent(String.self, forKey: .sectionId)
        title = try c.decode(String.self, forKey: .title)
        dueDate = try c.decodeIfPresent(String.self, forKey: .dueDate)
        position = try c.decode(Int.self, forKey: .position)
        commentCount = try c.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
        archivedAt = try c.decodeIfPresent(String.self, forKey: .archivedAt)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
        projectName = try c.decode(String.self, forKey: .projectName)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, position
        case projectId = "project_id"
        case sectionId = "section_id"
        case dueDate = "due_date"
        case commentCount = "comment_count"
        case archivedAt = "archived_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case projectName = "project_name"
    }
}

struct Comment: Codable, Identifiable, Equatable {
    let id: String
    let taskId: String
    var content: String
    var attachments: [Attachment]
    let createdAt: String
    let updatedAt: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        taskId = try c.decode(String.self, forKey: .taskId)
        content = try c.decode(String.self, forKey: .content)
        attachments = try c.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id, content, attachments
        case taskId = "task_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct Attachment: Codable, Identifiable, Equatable {
    let id: String
    let commentId: String
    let filename: String
    let contentType: String
    let size: Int
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, filename, size
        case commentId = "comment_id"
        case contentType = "content_type"
        case createdAt = "created_at"
    }

    var isImage: Bool {
        contentType.hasPrefix("image/")
    }
}

struct UpcomingTask: Codable, Identifiable, Equatable {
    let id: String
    let projectId: String
    let sectionId: String?
    let title: String
    let dueDate: String?
    let position: Int
    let commentCount: Int
    let createdAt: String
    let updatedAt: String
    let projectName: String

    enum CodingKeys: String, CodingKey {
        case id, title, position
        case projectId = "project_id"
        case sectionId = "section_id"
        case dueDate = "due_date"
        case commentCount = "comment_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case projectName = "project_name"
    }
}
