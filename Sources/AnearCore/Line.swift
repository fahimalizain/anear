import Foundation

/// One ambient line of text. `id` survives persistence so editing later can
/// update a line in place without losing identity.
public struct Line: Sendable, Equatable, Identifiable, Codable {
    public var id: UUID
    public var text: String

    public init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}
