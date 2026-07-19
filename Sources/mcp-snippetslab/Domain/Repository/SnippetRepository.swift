// MARK: - Repository Protocol

public protocol SnippetRepository: Sendable {
    func readFolders() throws -> [Folder]
    func readTags() throws -> [Tag]
    func readSnippetSummaries() throws -> [Snippet]
    func readSnippet(uuid: String) throws -> Snippet
    func searchSnippets(query: String) throws -> [Snippet]
    func createSnippet(
        title: String,
        content: String,
        language: String?,
        folderUUID: String?,
        tagUUIDs: [String],
        note: String?
    ) throws -> String
}
