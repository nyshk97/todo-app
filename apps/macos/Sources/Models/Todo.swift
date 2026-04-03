import Foundation

struct Todo: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    let date: String
    var completed: Bool
    var position: Int
    let carriedOver: Bool
    var duration: Int?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, date, completed, position, duration
        case carriedOver = "carried_over"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct TodosResponse: Codable {
    let todos: [Todo]
    let date: String
    let editable: Bool
}
