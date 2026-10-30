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
    /// A new conversation opening on its welcome: show it from the top.
    case top
    /// Scroll so this message's top is visible.
    case start(UUID)
    /// Stay put and offer this message below.
    case hold(UUID)

    /// - Parameter readingLatest: the message that was last before this
    ///   change, or the conversation's end, was on screen.
    static func after(_ messages: [ConversationMessage], previousCount: Int, readingLatest: Bool) -> ConversationReveal {
        guard messages.count > previousCount else { return .none }
        // Opening the stored conversation adds everything at once.
        if previousCount == 0 { return opensAtWelcome(messages) ? .top : .end }
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

    /// Only the welcome and Aurora's own cards so far: the opened
    /// conversation is read from its top, not its end.
    static func opensAtWelcome(_ messages: [ConversationMessage]) -> Bool {
        messages.first?.card?.kind == .welcome && !messages.hasUserMessages(atLeast: 1)
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
        case .end, .top: revealedStart = nil
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

    /// UIKit's keyboard completion can precede SwiftUI's final scroll insets
    /// and card layout. Reapply the latest reply's anchor when that layout
    /// changes, but never on a content-offset change or after manual scrolling.
    func afterLayoutChanged(from old: ConversationLayout, to new: ConversationLayout,
                            latestMessage: UUID?, holding: Bool) -> ConversationReveal {
        guard old.isMeasured, new.isMeasured, old != new else { return .none }
        return afterKeyboardDismissed(latestMessage: latestMessage, holding: holding)
    }
}

/// Layout only: scrolling itself must not cause another automatic reveal.
struct ConversationLayout: Equatable {
    var container: CGSize
    var contentHeight: CGFloat
    var topInset: CGFloat
    var bottomInset: CGFloat

    var isMeasured: Bool {
        container.width.isFinite && container.height.isFinite
            && container.width > 0 && container.height > 0
            && contentHeight.isFinite && contentHeight >= 0
            && topInset.isFinite && bottomInset.isFinite
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
