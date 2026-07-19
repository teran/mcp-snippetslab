public struct Tag: Codable, Sendable, Identifiable, Equatable {
    public let title: String
    public let uuid: String

    public var id: String { uuid }
}
