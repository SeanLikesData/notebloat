import Foundation

/// One tab in the scratchpad. Each tab holds a single free-form text
/// document. Persisted as JSON.
struct TabItem: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var content: String

    init(id: UUID = UUID(), name: String, content: String = "") {
        self.id = id
        self.name = name
        self.content = content
    }
}
