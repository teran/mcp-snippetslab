import Foundation

// MARK: - Composite Repository

internal final class CompositeSnippetRepository: SnippetRepository {
    private let reader: BackupSnippetRepository
    private let writer: NSKeyedArchiverSnippetWriter

    init(reader: BackupSnippetRepository, writer: NSKeyedArchiverSnippetWriter) {
        self.reader = reader
        self.writer = writer
    }

    func readFolders() throws -> [Folder] {
        try reader.readFolders()
    }

    func readTags() throws -> [Tag] {
        try reader.readTags()
    }

    func readSnippetSummaries() throws -> [Snippet] {
        try reader.readSnippetSummaries()
    }

    func readSnippet(uuid: String) throws -> Snippet {
        try reader.readSnippet(uuid: uuid)
    }

    func searchSnippets(query: String) throws -> [Snippet] {
        try reader.searchSnippets(query: query)
    }

    func createSnippet(
        title: String,
        content: String,
        language: String?,
        folderUUID: String?,
        tagUUIDs: [String],
        note: String?
    ) throws -> String {
        // Validate folderUUID exists in the library
        if let folderUUID {
            let folders = try reader.readFolders()
            guard folders.contains(where: { $0.uuid == folderUUID }) else {
                throw BackupSnippetRepository.Error.notFound("Folder \(folderUUID) not found in library")
            }
        }

        // Validate tagUUIDs exist in the library
        if !tagUUIDs.isEmpty {
            let tags = try reader.readTags()
            let validTagUUIDs = Set(tags.map(\.uuid))
            for tagUUID in tagUUIDs {
                guard validTagUUIDs.contains(tagUUID) else {
                    throw BackupSnippetRepository.Error.notFound("Tag \(tagUUID) not found in library")
                }
            }
        }

        return try writer.createSnippet(
            title: title,
            content: content,
            language: language,
            folderUUID: folderUUID,
            tagUUIDs: tagUUIDs,
            note: note
        )
    }
}
