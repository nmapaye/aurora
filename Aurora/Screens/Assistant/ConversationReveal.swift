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
        if let lastUser = added.lastIndex(where: \.isUser) {
            // The person's message and Aurora's reply can land in one update
            // when the reply is ready at once (quick actions). They just sent
            // it, so they are at the latest: show the reply's start, as when
            // it arrives on its own, not the end of a long card.
            let replyIndex = messages.index(after: lastUser)
            return replyIndex < messages.endIndex ? .start(messages[replyIndex].id) : .end
        }
        guard let first = added.first else { return .none }
        return readingLatest ? .start(first.id) : .hold(first.id)
    }
}

/// What a taller bottom area keeps in view. Right after a reply arrives the
/// bottom area can grow: the keyboard finishing its dismissal, Stop turning
/// back into Send, the quick actions becoming next steps. Whatever the reply
/// revealed has to stay in view through that.
struct ConversationFollow: Equatable {
    /// The reply whose start was revealed last; nil once the end was shown
    /// or the person scrolled.
    private(set) var revealedStart: UUID?

    mutating func revealed(_ reveal: ConversationReveal) {
        switch reveal {
        case .end: revealedStart = nil
        case .start(let id): revealedStart = id
        case .none, .hold: break
        }
    }

    /// The person scrolled, or (before iOS 18) the end came into view: where
    /// they read is theirs again.
    mutating func stopFollowing() { revealedStart = nil }

    /// - Parameter atEnd: the end was on screen when last known. On iOS 18
    ///   and later only the person's own scrolling updates it, so it is
    ///   still true after Aurora revealed a long reply's start.
    func afterBottomAreaGrew(from old: CGFloat, to new: CGFloat, atEnd: Bool, holding: Bool) -> ConversationReveal {
        guard new > old, atEnd, !holding else { return .none }
        // A short reply's start clamps to the end, so it still shows whole.
        if let revealedStart { return .start(revealedStart) }
        return .end
    }

    /// Keyboard dismissal changes the viewport independently of the bottom
    /// area's height. Keep only the latest reply's previously revealed start;
    /// a held reply or the person's own scrolling must never be overridden.
    func afterKeyboardDismissed(latestMessage: UUID?, holding: Bool) -> ConversationReveal {
        guard !holding, let revealedStart, revealedStart == latestMessage else { return .none }
        return .start(revealedStart)
    }
}

/// Which messages the conversation renders. It is a plain stack, not a lazy
/// one: on iOS 26.5 the lazy stack's estimated row heights kept the scroll
/// view re-adjusting its offset forever (an iPad hang after saving a draft
/// while reading earlier messages). A plain stack lays out every row, so it
/// shows the latest messages and reveals earlier ones in batches on request.
///
/// `start` is the first message shown; nil shows the latest.
enum ConversationWindow {
    static let latest = 40
    static let batch = 20

    /// Index of the first message shown. Always includes the latest.
    static func first(_ start: Int?, count: Int) -> Int {
        max(0, min(start ?? count, count - latest))
    }

    /// After the count changed. Added messages join below without moving
    /// the top; opening or clearing the conversation shows the latest again.
    static func start(_ start: Int?, count: Int, previousCount: Int) -> Int? {
        guard previousCount > 0, count > 0 else { return nil }
        return count > previousCount ? first(start, count: previousCount) : start
    }

    /// One batch earlier.
    static func earlier(_ start: Int?, count: Int) -> Int {
        max(0, first(start, count: count) - batch)
    }
}
