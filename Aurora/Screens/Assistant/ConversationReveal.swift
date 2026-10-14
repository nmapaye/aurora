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

/// The cap on how much the plain stack lays out, and the rows it renders.
extension ConversationWindow {
    /// Most messages rendered at once. Past it, showing an earlier batch
    /// leaves out the newest revealed batch rather than the latest, and a
    /// control where they were shows them again a batch at a time.
    static let cap = 120

    /// Indices rendered: the revealed earlier messages, then the latest.
    /// Two ranges when the cap left messages out between them.
    static func shown(_ start: Int?, count: Int) -> [Range<Int>] {
        let top = first(start, count: count)
        let latestStart = max(0, count - latest)
        let earlierEnd = top + cap - latest
        guard earlierEnd < latestStart else { return [top..<count] }
        return [top..<earlierEnd, latestStart..<count]
    }

    /// One batch later: brings back the left-out batch next to the shown
    /// earlier messages, and drops as many from the top. No change without
    /// a gap.
    static func later(_ start: Int?, count: Int) -> Int {
        let top = first(start, count: count)
        return max(top, min(top + batch, count - cap))
    }

    /// The rendered rows, in order. One pass over the shown messages, each
    /// compared only with the message before it.
    static func rows(_ messages: [ConversationMessage], start: Int?) -> [ConversationRow] {
        var rows: [ConversationRow] = []
        let ranges = shown(start, count: messages.count)
        rows.reserveCapacity(ranges.reduce(0) { $0 + $1.count })
        for (part, range) in ranges.enumerated() {
            for index in range {
                let message = messages[index]
                let afterGap = part > 0 && index == range.lowerBound
                let startsGroup = index == 0 || afterGap
                    || message.createdAt.timeIntervalSince(messages[index - 1].createdAt) > ConversationRow.groupGap
                rows.append(ConversationRow(message: message, startsGroup: startsGroup, afterGap: afterGap))
            }
        }
        return rows
    }
}

/// One rendered message.
struct ConversationRow: Identifiable {
    /// Messages further apart than this start a new group under their time.
    static let groupGap: TimeInterval = 300

    let message: ConversationMessage
    /// Shows its time: the first message, the first after left-out ones, or
    /// one more than five minutes after the message before it.
    let startsGroup: Bool
    /// The first of the latest messages, with left-out messages above it.
    let afterGap: Bool
    var id: UUID { message.id }
}

extension Collection where Element == ConversationMessage {
    /// Whether at least `count` of these are the person's own. Stops at the
    /// `count`th, so checking for the first few stays cheap however long the
    /// conversation is.
    func hasUserMessages(atLeast count: Int) -> Bool {
        lazy.filter(\.isUser).prefix(count).count == count
    }
}
