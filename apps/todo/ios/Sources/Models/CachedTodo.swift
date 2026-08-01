import Foundation
import SwiftData

@Model
final class CachedTodo {
    @Attribute(.unique) var id: String
    var title: String
    var date: String
    var completed: Bool
    var position: Int
    var carriedOver: Bool
    var createdAt: String
    var updatedAt: String

    init(
        id: String,
        title: String,
        date: String,
        completed: Bool,
        position: Int,
        carriedOver: Bool,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.completed = completed
        self.position = position
        self.carriedOver = carriedOver
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    convenience init(from todo: Todo) {
        self.init(
            id: todo.id,
            title: todo.title,
            date: todo.date,
            completed: todo.completed,
            position: todo.position,
            carriedOver: todo.carriedOver,
            createdAt: todo.createdAt,
            updatedAt: todo.updatedAt
        )
    }

    func apply(_ todo: Todo) {
        title = todo.title
        date = todo.date
        completed = todo.completed
        position = todo.position
        carriedOver = todo.carriedOver
        createdAt = todo.createdAt
        updatedAt = todo.updatedAt
    }

    func toTodo() -> Todo {
        Todo(
            id: id,
            title: title,
            date: date,
            completed: completed,
            position: position,
            carriedOver: carriedOver,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

@Model
final class CachedDate {
    @Attribute(.unique) var date: String
    var editable: Bool
    var lastFetchedAt: Date

    init(date: String, editable: Bool, lastFetchedAt: Date) {
        self.date = date
        self.editable = editable
        self.lastFetchedAt = lastFetchedAt
    }
}

enum PendingOperationKind: String {
    case create
    case update
    case delete
    case reorder
}

@Model
final class PendingOperation {
    @Attribute(.unique) var id: String
    var kind: String
    var todoId: String?
    var date: String
    var titlePayload: String?
    var completedPayload: Bool?
    var reorderItemsJSON: String?
    var createdAt: Date
    var retryCount: Int

    init(
        id: String = UUID().uuidString,
        kind: PendingOperationKind,
        todoId: String? = nil,
        date: String,
        titlePayload: String? = nil,
        completedPayload: Bool? = nil,
        reorderItemsJSON: String? = nil,
        createdAt: Date = .now,
        retryCount: Int = 0
    ) {
        self.id = id
        self.kind = kind.rawValue
        self.todoId = todoId
        self.date = date
        self.titlePayload = titlePayload
        self.completedPayload = completedPayload
        self.reorderItemsJSON = reorderItemsJSON
        self.createdAt = createdAt
        self.retryCount = retryCount
    }
}

struct ReorderItemPayload: Codable {
    let id: String
    let position: Int
}
