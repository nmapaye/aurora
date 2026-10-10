import AuroraCore
import Foundation

/// Where the conversation moves when messages are added. A new reply shows
/// its start, so a long card is read from its title and evidence rather than
/// from its last control. Someone reading earlier messages is never pulled
/// away; the new message waits below until they ask for it.
enum ConversationReveal: Equatable {
    case none
    /// The opened conversation, or the person's own message: show the end.
    case end
    /// Scroll so this message's top is visible.
    case start(UUID)
    /// Stay put and offer this message below.
    case hold(UUID)

    /// - Parameter readingLatest: the message that was last before this
    ///   change, or the conversation's end, was on screen.
    static func after(_ messages: [ConversationMessage], previousCount: Int, readingLatest: Bool) -> ConversationReveal {
        guard messages.count > previousCount else { return .none }
        // Opening the stored conversation adds everything at once.
        if previousCount == 0 { return .end }
        let added = messages[previousCount...]
        if added.contains(where: \.isUser) { return .end }
        guard let first = added.first else { return .none }
        return readingLatest ? .start(first.id) : .hold(first.id)
    }
}
