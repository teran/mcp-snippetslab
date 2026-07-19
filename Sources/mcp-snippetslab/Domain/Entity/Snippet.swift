// MARK: - Snippet

public struct Snippet: Codable, Sendable, Identifiable, Equatable {
    public let title: String?
    public let uuid: String
    public let folder: String?
    public let tags: [String]?
    public let dateCreated: String?
    public let dateModified: String?
    public let dateDeleted: String?
    public let fragments: [Fragment]?

    public var id: String { uuid }
}

// MARK: - Fragment

public struct Fragment: Codable, Sendable, Equatable {
    public let title: String?
    public let note: String?
    public let content: String?
    public let language: String?
    public let uuid: String?
    public let dateCreated: String?
    public let dateModified: String?
}
