import AuroraCore
import Foundation

struct ConversationStore {
    let directory: URL
    var url: URL { directory.appendingPathComponent("conversation.json") }
    func load() throws -> ConversationState {
        try StateStore.prepareExcludedDirectory(directory)
        guard FileManager.default.fileExists(atPath: url.path) else { return ConversationState() }
        let original = try Data(contentsOf: url)
        var value = try JSONDecoder().decode(ConversationState.self, from: original)
        guard value.version == 1 || value.version == 2 else { throw IntelligenceFailure.invalidOutput }
        if value.version == 1 {
            let backup = directory.appendingPathComponent("conversation.v1-source.json")
            if !FileManager.default.fileExists(atPath: backup.path) {
                try original.write(to: backup, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            value.version = 2
            do {
                try save(value)
                let verified = try JSONDecoder().decode(ConversationState.self, from: Data(contentsOf: url))
                guard verified == value else { throw IntelligenceFailure.invalidOutput }
            } catch {
                try original.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                throw error
            }
        }
        return value
    }
    func removeMigrationSource() throws {
        let backup = directory.appendingPathComponent("conversation.v1-source.json")
        if FileManager.default.fileExists(atPath: backup.path) { try FileManager.default.removeItem(at: backup) }
    }
    func save(_ value: ConversationState) throws {
        try StateStore.prepareExcludedDirectory(directory)
        try JSONEncoder().encode(value).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
