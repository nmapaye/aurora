import AuroraCore
import EventKit
import SwiftUI
import UIKit

struct AssistantView: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AssistantModel.self) private var assistant
    @State private var dictation = OnDeviceDictation()
    @State private var input = ""
    @State private var showHealthConnection = false
    /// How far the software keyboard reaches up from the screen's bottom.
    @State private var keyboardOverlap: CGFloat = 0
    /// Messages at least partly on screen, and whether the end is.
    /// Which messages, and whether the end, are on screen. Held by
    /// reference, not as view state: they change on every scroll and are
    /// only read when a message arrives. As state, each change re-ran the
    /// conversation's layout, and on iOS 26.5 at the largest text that
    /// flipped them again, so the main thread never went idle.
    @State private var visibility = Visibility()
    fileprivate final class Visibility {
        var messages: Set<UUID> = []
        var end = true
        /// Within most of a screen of the end (iOS 18 and later only).
        var nearEnd = true
        /// Whether the end really is on screen now. `end` stays true while
        /// Aurora shows a long reply's start; this one doesn't, so a taller
        /// bottom area can't pull the page to the end past that start.
        var endOnScreen = true
        /// The person's own message just showed the end and they haven't
        /// scrolled since, so the reply is what they are waiting to read,
        /// even if the scroll to the end hasn't finished when it arrives.
        var awaitingReply = false
        /// The person is dragging or flinging the conversation (iOS 18 and
        /// later). Only their own scrolling changes where they are reading;
        /// Aurora revealing a long card's start doesn't move them away from
        /// the latest message.
        var userScrolling = false {
            didSet { if userScrolling { awaitingReply = false } }
        }
    }
    @State private var viewportHeight: CGFloat = 0
    /// Where the visible part of the conversation ends, in its own
    /// coordinates: above the bottom area's inset (iOS 18 and later; nil
    /// uses the viewport's height).
    @State private var visibleBottom: CGFloat?
    /// The first message added while earlier messages were being read.
    @State private var heldMessage: UUID?
    /// The held message's top is below the visible area. Measured, so "New
    /// message below" never shows while the message is on screen.
    @State private var heldBelow = false
    private static let top = "top"
    /// The first message shown (`ConversationWindow`); nil shows the latest.
    @State private var windowStart: Int?
    @State private var composerWidth: CGFloat = 0
    /// The fixed bottom area's height; it changes when quick actions hide
    /// for card editing and come back.
    @State private var composerHeight: CGFloat = 0
    @FocusState private var composerFocused: Bool
    private static let viewport = "conversation"

    var body: some View {
        @Bindable var assistant = assistant
        @Bindable var router = router
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        top(proxy)
                        messageList(proxy)
                        // Stop lives in the composer, so it stays reachable
                        // while earlier messages are being read.
                        if assistant.processing {
                            HStack(spacing: Metrics.sm) {
                                AuroraActivity(active: true).frame(width: 54, height: 36)
                                Text(assistant.status).font(.subheadline).foregroundStyle(Palette.textSecondary)
                                Spacer(minLength: 0)
                            }
                            .accessibilityElement(children: .combine)
                        }
                        if let failure = assistant.failure ?? dictation.error {
                            Text(failure).foregroundStyle(Palette.destructive).font(.footnote)
                                .accessibilityIdentifier("assistant-error")
                        }
                        Color.clear.frame(height: 1).id("bottom")
                            .trackingVisibility(onScreen) { visible in
                                visibility.end = visible; visibility.endOnScreen = visible
                                if visible && heldMessage != nil { heldMessage = nil }
                            }
                            .onDisappear { visibility.end = false; visibility.endOnScreen = false }
                        // QA showed the conversation could not scroll a card's
                        // Save above the composer while the number pad was up:
                        // its extent stopped short by about the keyboard. While
                        // a card field is edited, extend the end by the keyboard
                        // overlap so Save can always be scrolled into view.
                        if editingCard && keyboardOverlap > 0 {
                            Color.clear.frame(height: keyboardOverlap).accessibilityHidden(true)
                        }
                    }
                    .frame(maxWidth: Metrics.contentMaxWidth).frame(maxWidth: .infinity)
                    .padding(Metrics.lg)
                }
                // Opens at the latest message, including right after the
                // launch welcome; a new conversation opens on its welcome card,
                // read from the top. Scrolled once rather than with
                // defaultScrollAnchor(.bottom): on iOS 26.5 that anchor, with
                // the lazy stack's estimated heights, kept the conversation
                // re-laying out so the main thread never went idle.
                .onAppear { if !ConversationReveal.opensAtWelcome(assistant.conversation.messages) { proxy.scrollTo("bottom", anchor: .bottom) } }
                .coordinateSpace(.named(Self.viewport))
                .trackingConversationEnd(visibility, conversationEndChanged)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if viewportHeight != $0 { viewportHeight = $0 } }
                .scrollDismissesKeyboard(.interactively)
                .overlay(alignment: .bottom) { newMessageBelow(proxy) }
                .animation(Motion.content(reduceMotion: reduceMotion), value: showsNewBelow)
                // A taller bottom area would otherwise cover the end the person
                // was reading; keep the end above it. Only when the end really
                // is on screen, never past a reply's start.
                .onChange(of: composerHeight) { old, new in
                    if new > old && visibility.endOnScreen && heldMessage == nil { reveal(proxy, "bottom", anchor: .bottom) }
                }
                .onChange(of: assistant.conversation.messages.count) { old, _ in messagesChanged(from: old, proxy) }
            }
            .background(Palette.screen)
            // A solid bar: on iOS 26 the default only fades, and scrolled
            // cards stayed readable behind the title and buttons.
            .toolbarBackground(Palette.screen, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationTitle("Aurora")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 7) {
                        // The crisp mark at rest; the flowing ribbon only while working.
                        ZStack {
                            if assistant.processing {
                                AuroraActivity(active: true, subdued: true).frame(width: 28, height: 20)
                                    .transition(.opacity)
                            } else {
                                AuroraMark().frame(width: 22, height: 22).transition(.opacity)
                            }
                        }
                        .frame(width: 28, height: 22)
                        .animation(Motion.content(reduceMotion: reduceMotion), value: assistant.processing)
                        Text("Aurora").font(.headline)
                    }
                    .accessibilityElement(children: .ignore).accessibilityLabel("Aurora")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { assistant.historySheet = .history } label: { Image(systemName: "clock.arrow.circlepath") }
                        .accessibilityLabel("Your records").accessibilityIdentifier("assistant-history")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { assistant.showAssistantSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Aurora settings").accessibilityIdentifier("assistant-settings")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            // Inside the NavigationStack: placed over it, the glow's full-window
            // host took every accessibility hit on iPadOS 26, so nothing under
            // it was reachable by VoiceOver or UI tests.
            .overlay { AuroraEdgeGlow(active: assistant.processing).allowsHitTesting(false).accessibilityHidden(true).ignoresSafeArea() }
        }
        .task { await assistant.start(app: app) }
        .modifier(ConversationObservers(assistant: assistant, router: router, app: app, dictation: dictation,
                                        input: $input, keyboardOverlap: $keyboardOverlap, composerFocused: composerFocused))
        .modifier(ConversationSheets(assistant: assistant, router: router, app: app, showHealthConnection: $showHealthConnection, onDismiss: runRequestedErase))
    }

    /// A message was added or removed: reveal it, or hold it below while
    /// earlier messages are being read.
    private func messagesChanged(from old: Int, _ proxy: ScrollViewProxy) {
        let messages = assistant.conversation.messages
        let previous = old > 0 && old <= messages.count ? messages[old - 1] : nil
        let readingLatest = visibility.end || visibility.nearEnd || (previous?.isUser == true && visibility.awaitingReply)
            || previous.map { visibility.messages.contains($0.id) } == true
        windowStart = ConversationWindow.start(windowStart, count: messages.count, previousCount: old)
        let reveal = ConversationReveal.after(messages, previousCount: old, readingLatest: readingLatest)
        switch reveal {
        case .none:
            if messages.isEmpty { heldMessage = nil }
        case .end:
            // Going to the end anyway: drop revealed earlier messages so
            // the plain stack doesn't grow without bound.
            heldMessage = nil; windowStart = nil
            visibility.awaitingReply = old > 0
            self.reveal(proxy, "bottom", anchor: .bottom)
        case .top:
            heldMessage = nil
            Task { @MainActor in proxy.scrollTo(Self.top, anchor: .top) }
        case .start(let id):
            heldMessage = nil; visibility.awaitingReply = false
            self.reveal(proxy, id, anchor: .top)
        case .hold(let id):
            // Keep the earliest unseen message; reading resumes there. The
            // capsule and its announcement wait for its measured position.
            if heldMessage == nil { heldMessage = id; heldBelow = false }
        }
        // A held reply is announced by its capsule instead.
        var held = false
        if case .hold = reveal { held = true }
        if old > 0, messages.count > old { repliesArrived(messages[old...], announce: !held) }
    }

    /// Aurora's reply arrived. A new draft takes the keyboard down so the
    /// card shows from its title, not cut off above a letter keyboard it
    /// doesn't use. VoiceOver hears the reply's title; focus stays put.
    private func repliesArrived(_ added: ArraySlice<ConversationMessage>, announce: Bool) {
        guard let reply = added.first(where: { !$0.isUser }) else { return }
        let drafts: Set<AssistantCard.Kind> = [.caffeineDraft, .sleepDraft, .energyCheckIn]
        if added.contains(where: { $0.card.map { drafts.contains($0.kind) } == true }) { composerFocused = false }
        if announce { Self.announce(reply.card?.title ?? reply.text) }
    }

    /// Spoken at high priority so the keyboard leaving or a layout change
    /// doesn't cut it off.
    static func announce(_ text: String) {
        var message = AttributedString(text)
        message.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(message).post()
    }

    /// From the scroll view's geometry (iOS 18 and later).
    private func conversationEndChanged(_ now: ConversationEnd) {
        visibility.endOnScreen = now.end
        if visibility.userScrolling || now.end {
            visibility.end = now.end
            visibility.nearEnd = now.nearEnd || now.end
        }
        if now.end && heldMessage != nil { heldMessage = nil }
        if visibleBottom != now.visibleBottom { visibleBottom = now.visibleBottom }
    }

    /// The welcome, then the control for messages left out of the stack.
    /// One member, so the body stays quick to type-check.
    @ViewBuilder private func top(_ proxy: ScrollViewProxy) -> some View {
        identity
        if ConversationWindow.first(windowStart, count: assistant.conversation.messages.count) > 0 {
            Button { showEarlierMessages(proxy) } label: {
                Label("Show earlier messages", systemImage: "arrow.up")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, Metrics.md)
                    .frame(minHeight: Metrics.minimumTouchTarget)
            }
            .buttonStyle(CapsuleActionStyle())
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("assistant-show-earlier")
        }
    }

    /// Adds one batch above and keeps the place: the message that was first
    /// is put back at the top once the batch is laid out.
    private func showEarlierMessages(_ proxy: ScrollViewProxy) {
        let messages = assistant.conversation.messages
        let first = ConversationWindow.first(windowStart, count: messages.count)
        guard first > 0 else { return }
        let top = messages[first].id
        windowStart = ConversationWindow.earlier(windowStart, count: messages.count)
        Task { @MainActor in proxy.scrollTo(top, anchor: .top) }
    }

    /// The rendered messages, with the control for any the cap left out.
    /// One member, so the body stays quick to type-check.
    private func messageList(_ proxy: ScrollViewProxy) -> some View {
        ForEach(ConversationWindow.rows(assistant.conversation.messages, start: windowStart)) { row in
            if row.afterGap { showLaterButton(proxy) }
            conversationRow(row)
        }
    }

    /// Where the cap left messages out, above the latest.
    private func showLaterButton(_ proxy: ScrollViewProxy) -> some View {
        Button { showLaterMessages(proxy) } label: {
            Label("Show later messages", systemImage: "arrow.down")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, Metrics.md)
                .frame(minHeight: Metrics.minimumTouchTarget)
        }
        .buttonStyle(CapsuleActionStyle())
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("assistant-show-later")
    }

    /// Brings back one left-out batch below the earlier messages and keeps
    /// the place: the message just above the control stays where it was.
    private func showLaterMessages(_ proxy: ScrollViewProxy) {
        let messages = assistant.conversation.messages
        let shown = ConversationWindow.shown(windowStart, count: messages.count)
        guard shown.count > 1, let last = shown.first?.last else { return }
        let anchor = messages[last].id
        windowStart = ConversationWindow.later(windowStart, count: messages.count)
        Task { @MainActor in proxy.scrollTo(anchor, anchor: .bottom) }
    }

    @ViewBuilder private var identity: some View {
        // Stops at the first of the person's messages, near the start.
        if !assistant.conversation.messages.hasUserMessages(atLeast: 1) {
            VStack(alignment: .leading, spacing: 6) {
                Text("A little clarity for your day.").font(.title2.weight(.medium))
                Text(assistant.intelligenceName).font(.caption).foregroundStyle(Palette.textSecondary)
                if app.state.demoMode { Text("Sample Data · for exploration").font(.caption).foregroundStyle(Palette.caffeineAccent) }
            }.padding(.vertical, 6)
            // A new conversation opens here, with its welcome card below.
            .id(Self.top)
        }
    }
    /// `startsGroup` comes from `ConversationWindow.rows`, worked out in one
    /// pass rather than by finding each message in the whole history.
    @ViewBuilder private func messageView(_ message: ConversationMessage, startsGroup: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if startsGroup {
                Text(message.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(Palette.textSecondary)
            }
            if let card = message.card, !message.isUser {
                AssistantCardView(message: message, card: card)
            } else {
                Text(message.text).textSelection(.enabled)
                    .foregroundStyle(Palette.textPrimary).padding(16)
                    .background(message.isUser ? Palette.selectionFill : Palette.card, in: RoundedRectangle(cornerRadius: 22))
                    .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
                    .accessibilityLabel("\(message.isUser ? "You" : "Aurora"): \(message.text)")
                // Legacy text remains as originally shown. Do not attach live
                // charts or executable proposals to old messages after migration.
            }
            if message.suggestionKey != nil { Button("Dismiss suggestion") { assistant.dismissSuggestion(message) }.font(.caption).frame(minHeight: 44) }
        }
    }

    /// At least partly inside the conversation's visible height.
    private func onScreen(_ proxy: GeometryProxy) -> Bool {
        let frame = proxy.frame(in: .named(Self.viewport))
        return frame.maxY > 0 && frame.minY < viewportHeight
    }

    /// Runs after this update, so a message added in it has been laid out.
    /// Short and interruptible; instant under Reduce Motion.
    /// The erase confirmed in a sheet, once that sheet has closed.
    private func runRequestedErase() {
        guard assistant.takeEraseRequest() else { return }
        if !app.eraseAllLocalData(assistant: assistant) { assistant.failure = app.mutationFailure }
    }

    private func reveal<ID: Hashable>(_ proxy: ScrollViewProxy, _ id: ID, anchor: UnitPoint) {
        Task { @MainActor in
            withAnimation(Motion.content(reduceMotion: reduceMotion)) { proxy.scrollTo(id, anchor: anchor) }
        }
    }

    private var showsNewBelow: Bool { heldMessage != nil && heldBelow }

    /// Only on the held message's row, so one row is measured, not every
    /// row (a geometry observer per row kept iOS 26.5 laying out forever).
    /// In a background, so adding it doesn't change the row's identity.
    @ViewBuilder private func heldTracker(_ id: UUID) -> some View {
        if id == heldMessage {
            let edge = visibleBottom ?? viewportHeight
            let space = Self.viewport
            Color.clear.onGeometryChange(for: Bool.self) { proxy in
                proxy.frame(in: .named(space)).minY >= edge
            } action: { below in heldMoved(below: below) }
        }
    }

    /// The capsule shows only while the held message starts below the
    /// visible area, so it never covers the message's own time row or its
    /// controls. Once its top is in view, it has been seen.
    private func heldMoved(below: Bool) {
        if !below { heldMessage = nil; heldBelow = false; return }
        guard !heldBelow else { return }
        heldBelow = true
        Self.announce("New message below")
    }

    @ViewBuilder private func newMessageBelow(_ proxy: ScrollViewProxy) -> some View {
        if let held = heldMessage, heldBelow {
            Button {
                heldMessage = nil; heldBelow = false
                reveal(proxy, held, anchor: .top)
            } label: {
                Label("New message below", systemImage: "arrow.down")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, Metrics.md)
                    .frame(minHeight: Metrics.minimumTouchTarget)
            }
            .buttonStyle(CapsuleActionStyle())
            .padding(.bottom, Metrics.xs)
            .transition(.opacity)
            .accessibilityHint("Shows the start of the newest message.")
            .accessibilityIdentifier("assistant-new-below")
        }
    }

    /// While a card's own field is being edited, the inset rides above the
    /// keyboard. Keep only the composer field so the card's Save stays
    /// visible and swipes can't land on quick actions.
    private var editingCard: Bool { assistant.editingCardField && !composerFocused }

    /// The bottom area. Only `$input` is passed, never read here: the draft
    /// lives in `ConversationComposer` so a keystroke re-renders the bar,
    /// not every message. Re-running the whole conversation per keystroke
    /// left CI's simulator behind on typing when Send was tapped.
    private var composer: some View {
        ConversationComposer(input: $input, focused: $composerFocused, composerWidth: $composerWidth,
                             composerHeight: $composerHeight, showHealthConnection: $showHealthConnection,
                             dictation: dictation, editingCard: editingCard)
    }

    /// The keyboard's end frame against its screen. A hardware keyboard's
    /// offscreen frame gives zero.
    fileprivate static func keyboardOverlap(_ note: Notification) -> CGFloat {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return 0 }
        guard let screen = note.object as? UIScreen else { return frame.height }
        return max(0, screen.bounds.maxY - frame.minY)
    }

    /// One message. Its own member so the conversation's body stays quick to
    /// type-check (Xcode 26.6 in CI). Next steps are in the bottom row, never
    /// here: a row changing height off screen as a reply arrived kept the
    /// lazy conversation laying out forever.
    private func conversationRow(_ row: ConversationRow) -> some View {
        let message = row.message
        return messageView(message, startsGroup: row.startsGroup)
        .id(message.id)
        .background { heldTracker(message.id) }
        .trackingVisibility(onScreen) { visible in
            if visible { visibility.messages.insert(message.id) } else { visibility.messages.remove(message.id) }
            if visible && heldMessage == message.id { heldMessage = nil }
        }
        .onDisappear { visibility.messages.remove(message.id) }
    }
}

private extension View {
    /// The conversation's column: at most `contentMaxWidth`, centered, `lg`
    /// from the edges, matching the message list.
    func conversationColumn() -> some View {
        frame(maxWidth: Metrics.contentMaxWidth).frame(maxWidth: .infinity).padding(.horizontal, Metrics.lg)
    }
}

/// Quick actions and the new-message control: a card capsule whose press
/// and disabled states show at once.
private struct CapsuleActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { CapsuleActionBody(configuration: configuration) }
}

private struct CapsuleActionBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .foregroundStyle(isEnabled ? Palette.textPrimary : Palette.primaryButtonDisabledText)
            .background(Palette.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.cardBorder))
            .contentShape(Capsule())
            .pressFeedback(configuration.isPressed)
    }
}

/// Quick action tiles: a card surface with the shared press feedback.
private struct TileActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { TileActionBody(configuration: configuration) }
}

private struct TileActionBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.controlRadius + 2, style: .continuous)
        configuration.label
            .foregroundStyle(isEnabled ? Palette.textPrimary : Palette.primaryButtonDisabledText)
            .background(Palette.card, in: shape)
            .overlay(shape.strokeBorder(Palette.cardBorder))
            .contentShape(shape)
            .pressFeedback(configuration.isPressed)
    }
}

/// A small identity at rest; a brighter ribbon accompanies actual processing.
struct AuroraActivity: View {
    let active: Bool
    var subdued = false
    /// False draws the Reduce Motion treatment (Design Gallery review).
    var allowsMotion = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        if active && allowsMotion && !reduceMotion && scenePhase == .active {
            TimelineView(.animation(minimumInterval: Motion.decorationFrameInterval)) { timeline in
                ribbon(phase: timeline.date.timeIntervalSinceReferenceDate)
            }
        } else {
            ribbon(phase: 0)
        }
    }

    private func ribbon(phase: Double) -> some View {
        Canvas { context, size in
            let speed = subdued ? 0.35 : 0.8
            for band in 0..<3 {
                var path = Path()
                for step in 0...60 {
                    let x = size.width * Double(step) / 60
                    let y = size.height * (0.5 + 0.18 * sin(Double(step) / 10 + phase * speed + Double(band)))
                    if step == 0 { path.move(to: .init(x: x, y: y)) }
                    else { path.addLine(to: .init(x: x, y: y)) }
                }
                let brightness = (subdued ? 0.45 : 0.65) + 0.08 * sin(phase * speed + Double(band))
                let color = Palette.auroraColors[band]
                context.stroke(path, with: .linearGradient(.init(colors: [.clear, color.opacity(brightness), .clear]), startPoint: .zero, endPoint: .init(x: size.width, y: 0)), style: .init(lineWidth: size.height * 0.17, lineCap: .round))
            }
        }
        .blur(radius: subdued ? 1 : 3)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Your records. Every screen is pushed in this sheet's own stack and keeps
/// the system bar, so Back and the edge swipe work; Done sits trailing on
/// the root, as in every other sheet.
struct AssistantToolsView: View {
    let destination: AssistantIntent
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if destination == .logSleep { SleepHistoryView() }
                else if destination == .logCaffeine { CaffeineHistoryView() }
                else { records }
            }
            .toolbar { done }
        }
        .pageSizedSheet()
    }

    private var records: some View {
        List {
            Section {
                row("Caffeine", symbol: "cup.and.saucer", id: "records-caffeine") { CaffeineHistoryView() }
                // Sleep's own "All sleep entries" holds the full list.
                row("Sleep", symbol: "bed.double", id: "records-sleep") { SleepView(pushed: true) }
                row("Insights", symbol: "chart.bar", id: "records-insights") { InsightsView(pushed: true) }
            }
            .auroraRows()
            Section {
                row(SettingsView.recordsTitle, symbol: "lock", id: "records-settings") { SettingsView(pushed: true) }
            }
            .auroraRows()
        }
        .auroraGroupedList()
        .navigationTitle("Your records")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row<Destination: View>(_ title: String, symbol: String, id: String, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            Label(title, systemImage: symbol)
        }
        .accessibilityIdentifier(id)
    }

    private var done: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
    }
}

private extension View {
    /// Per-message visibility, used only before iOS 18. On iOS 26.5 a
    /// visibility observer on every message kept the lazy conversation
    /// laying out forever (the main thread never went idle), whether it was
    /// onGeometryChange or onScrollVisibilityChange.
    @ViewBuilder
    func trackingVisibility(_ onScreen: @escaping (GeometryProxy) -> Bool, action: @escaping (Bool) -> Void) -> some View {
        if #available(iOS 18, *) {
            self
        } else {
            onGeometryChange(for: Bool.self, of: onScreen, action: action)
        }
    }

    /// On iOS 18 and later, one observer on the scroll view says whether the
    /// end of the conversation is on screen, whether it is within most of a
    /// screen of it (still reading the latest message), and where the
    /// visible area ends above the bottom inset.
    @ViewBuilder
    func trackingConversationEnd(_ visibility: AssistantView.Visibility, _ action: @escaping (ConversationEnd) -> Void) -> some View {
        if #available(iOS 18, *) {
            onScrollPhaseChange { _, phase in
                visibility.userScrolling = phase == .interacting || phase == .decelerating
            }
            .onScrollGeometryChange(for: ConversationEnd.self) { geometry in
                let maxOffset = geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom - geometry.containerSize.height
                let gap = max(0, maxOffset - geometry.contentOffset.y - geometry.contentInsets.top)
                return ConversationEnd(end: gap <= 24, nearEnd: gap < geometry.containerSize.height * 0.75,
                                       visibleBottom: geometry.containerSize.height - geometry.contentInsets.bottom)
            } action: { _, now in
                action(now)
            }
        } else {
            self
        }
    }
}

private struct ConversationEnd: Equatable {
    var end: Bool
    var nearEnd: Bool
    /// The visible area's bottom edge in the scroll view's own space.
    var visibleBottom: CGFloat
}

/// The conversation's sheets. A modifier of its own: chained on the body
/// they made it too slow to type-check for CI's Xcode 26.6.
private struct ConversationSheets: ViewModifier {
    @Bindable var assistant: AssistantModel
    @Bindable var router: Router
    let app: AppModel
    @Binding var showHealthConnection: Bool
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $assistant.showSleepEntry) {
                SleepEntrySheet(mode: .new) { draft in
                    app.addManualSleep(draft)
                    if app.mutationFailure == nil { assistant.append("Sleep session saved.") }
                    else { assistant.failure = app.mutationFailure }
                } onDelete: {}
            }
            .sheet(isPresented: $assistant.showAssistantSettings, onDismiss: onDismiss) { AssistantSettingsView(assistant: assistant) }
            .sheet(isPresented: $showHealthConnection) { HealthConnectionView() }
            .sheet(isPresented: $assistant.showCalendarSettings) { CalendarConnectionsView(service: assistant.calendars) }
            .sheet(item: $assistant.historySheet, onDismiss: onDismiss) { intent in
                if intent == .reactionTest { ReactionTestView() }
                else if intent == .settings { SettingsView() }
                else { AssistantToolsView(destination: intent) }
            }
            .fullScreenCover(isPresented: $router.showReactionTest) { ReactionTestView() }
    }
}

/// What the conversation reacts to: scene changes, drafts, records, the
/// keyboard, calendars and routing. A modifier of its own for the same
/// type-checking reason as `ConversationSheets`.
private struct ConversationObservers: ViewModifier {
    let assistant: AssistantModel
    let router: Router
    let app: AppModel
    let dictation: OnDeviceDictation
    @Binding var input: String
    @Binding var keyboardOverlap: CGFloat
    let composerFocused: Bool
    @Environment(\.scenePhase) private var phase

    func body(content: Content) -> some View {
        content
            // Becoming active refreshes through AppModel's shared scheduler.
            // An open draft's values reach its card here, not per edit, so a
            // relaunch's expired card shows what was last entered.
            .onChange(of: phase) { _, value in
                if value != .active { dictation.stop(); assistant.releaseWarmResources(); assistant.clearCardFocus(); assistant.captureDraft(app: app) }
            }
            .onChange(of: app.state.vigilanceSessions) { old, new in
                if assistant.historySheet == .reactionTest, new.contains(where: { record in !RecordID.isSample(record.id) && !old.contains(where: { $0.id == record.id }) }) { assistant.reactionCompleted(app: app) }
            }
            .onChange(of: app.state.sleeps) { old, _ in assistant.sleepChanged(app: app, before: old) }
            // A drink logged today can answer a follow-up still ahead.
            .onChange(of: app.state.doses) { _, _ in Task { await assistant.syncRepeatDrinkNotifications(app: app) } }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                keyboardOverlap = AssistantView.keyboardOverlap(note)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardOverlap = 0 }
            .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
                Task { await assistant.calendars.refreshCalendars(); await assistant.foreground(app: app) }
            }
            .onChange(of: composerFocused) { _, focused in
                if focused { assistant.prepareForInput() }
            }
            .onChange(of: dictation.transcript) { _, text in input = text }
            .onChange(of: router.showSettings) { _, value in if value { assistant.showAssistantSettings = true; router.showSettings = false } }
            .onChange(of: router.sleepPath) { _, path in if !path.isEmpty { assistant.historySheet = .logSleep; router.sleepPath = [] } }
            .onChange(of: router.logPath) { _, path in if !path.isEmpty { assistant.historySheet = .logCaffeine; router.logPath = [] } }
    }
}

/// Hint, quick actions and composer. Its own view so the draft's
/// keystrokes re-evaluate only this bar, not the conversation above it.
private struct ConversationComposer: View {
    @Environment(AppModel.self) private var app
    @Environment(AssistantModel.self) private var assistant
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var input: String
    var focused: FocusState<Bool>.Binding
    @Binding var composerWidth: CGFloat
    @Binding var composerHeight: CGFloat
    @Binding var showHealthConnection: Bool
    let dictation: OnDeviceDictation
    let editingCard: Bool

    private var inputEmpty: Bool { input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Hint, quick actions and composer share the conversation column, so on
    /// iPad they line up with the cards instead of spanning the window.
    var body: some View {
        VStack(spacing: Metrics.xs) {
            if !editingCard, !typeSize.isAccessibilitySize, !assistant.conversation.messages.hasUserMessages(atLeast: 3) {
                Text("Start with a quick action, or ask in your own words.")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, Metrics.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .conversationColumn()
            }
            if !editingCard { quickActions }
            field
        }
        .padding(.vertical, Metrics.xs)
        // Solid like the header: the material let the next message's pill
        // show through as a sliver above the quick actions. Extends under
        // the home indicator.
        .background(Palette.screen)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { composerWidth = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { composerHeight = $0 }
        // The inset never scrolls, so uncapped accessibility sizes left the
        // conversation a sliver of the screen. Messages and cards still scale fully.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private var field: some View {
        HStack(alignment: .bottom, spacing: Metrics.sm) {
            TextField("", text: $input, axis: .vertical)
                .lineLimit(1...5).focused(focused).accessibilityLabel("Message Aurora").accessibilityIdentifier("assistant-composer")
                .submitLabel(.send).onSubmit { send() }
                .frame(minHeight: Metrics.minimumTouchTarget)
            Button {
                if dictation.recording { dictation.stop() } else { Task { await dictation.start() } }
            } label: { Image(systemName: dictation.recording ? "stop.circle.fill" : "mic").font(.system(size: 20)).frame(width: Metrics.minimumTouchTarget, height: Metrics.minimumTouchTarget) }
                .accessibilityLabel(dictation.recording ? "Stop local dictation" : "Dictate on device")
            sendOrStop
        }
        .padding(.horizontal, Metrics.md).padding(.vertical, Metrics.xs)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.heroRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metrics.heroRadius, style: .continuous).strokeBorder(focused.wrappedValue ? Palette.tint : Palette.cardBorder))
        // The whole surface focuses the field, not only its text line.
        .contentShape(RoundedRectangle(cornerRadius: Metrics.heroRadius, style: .continuous))
        .onTapGesture { focused.wrappedValue = true }
        .conversationColumn()
    }

    /// Send becomes Stop the moment work starts, and back when it ends.
    @ViewBuilder private var sendOrStop: some View {
        if assistant.processing {
            Button { assistant.cancel() } label: {
                Image(systemName: "stop.fill").font(.system(size: 20, weight: .semibold))
                    .frame(width: Metrics.minimumTouchTarget, height: Metrics.minimumTouchTarget)
                    .background(Palette.secondaryButton, in: Circle())
                    .foregroundStyle(Palette.secondaryButtonText)
            }
            .accessibilityLabel("Stop").accessibilityHint("Ends this request. Nothing is saved.")
            .accessibilityIdentifier("assistant-stop")
        } else {
            Button(action: send) {
                Image(systemName: "arrow.up").font(.system(size: 20, weight: .semibold))
                    .frame(width: Metrics.minimumTouchTarget, height: Metrics.minimumTouchTarget)
                    .background(inputEmpty ? Palette.primaryButtonDisabled : Palette.tint, in: Circle())
                    .foregroundStyle(inputEmpty ? Palette.primaryButtonDisabledText : Palette.primaryButtonText)
            }
            .disabled(inputEmpty)
            .accessibilityLabel("Send to Aurora").accessibilityIdentifier("assistant-send")
        }
    }

    /// Scrolls past the column's edges, but its first action starts in line
    /// with the cards and composer.
    /// Four equal tiles that fit without scrolling: the newest answer's next
    /// steps, then everyday actions. Everything else is in Settings, the
    /// history button, or a request.
    private var quickActions: some View {
        // Always one row: wrapping at large text would grow the fixed bottom
        // area and squeeze the conversation. Labels shrink a little instead.
        // While typing, the same row offers what matches the words so far,
        // so a request never depends on knowing its exact wording. The tiles'
        // labels stay laid out underneath, hidden, so the row keeps its
        // height: at the largest text a taller row shrinking as a message was
        // sent left the conversation scrolled onto empty space.
        let typed = Capabilities.matching(input)
        let columns = Array(repeating: GridItem(.flexible(), spacing: Metrics.xs), count: 4)
        let tiles = Capabilities.bottomRow(after: nextStepCard, clock: app.clock)
        return LazyVGrid(columns: columns, spacing: Metrics.xs) {
            ForEach(tiles) { tile in
                if typed.isEmpty { rowTile(tile.capability, isNextStep: tile.isNextStep) } else { tileLabel(tile.capability.shortTitle, symbol: tile.capability.symbol).hidden() }
            }
        }
        .overlay {
            if !typed.isEmpty {
                LazyVGrid(columns: columns, spacing: Metrics.xs) { ForEach(typed) { suggestion($0) } }
            }
        }
        .padding(.horizontal, Metrics.columnInset(containerWidth: composerWidth))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("assistant-quick-actions")
    }
    /// A matching action while typing: sends its request in place of the text.
    private func suggestion(_ capability: Capability) -> some View {
        Button {
            input = ""
            assistant.send(capability.phrase, app: app)
        } label: {
            VStack(spacing: Metrics.xxs) {
                Image(systemName: capability.symbol).font(.body.weight(.semibold)).foregroundStyle(Palette.tint)
                Text(capability.title).font(.caption.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.7).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 56, maxHeight: .infinity)
        }
        .buttonStyle(TileActionStyle())
        .disabled(assistant.processing)
        .accessibilityLabel(capability.title)
        .accessibilityHint("Suggested from what you typed.")
        .accessibilityIdentifier("assistant-suggest-\(capability.intent.rawValue)")
    }
    /// The newest answer's card while its next steps can be offered: nothing
    /// in progress and no card field being edited. Derived, never saved.
    private var nextStepCard: AssistantCard? {
        guard let last = assistant.conversation.messages.last, !last.isUser, let card = last.card,
              !assistant.processing, assistant.pendingMessageID == nil, !assistant.editingCardField else { return nil }
        return card
    }
    /// Every tile is the same height whatever its symbol: the icon sits over
    /// one reserved line of body text. Symbols differ in height, so a row
    /// that resized as next steps replaced the tiles re-anchored the
    /// conversation to its end and scrolled a new card's title away.
    private func tileLabel(_ short: String, symbol: String) -> some View {
        VStack(spacing: Metrics.xxs) {
            Text(verbatim: " ").font(.body.weight(.semibold)).hidden()
                .overlay { Image(systemName: symbol).font(.body.weight(.semibold)).foregroundStyle(Palette.tint) }
            Text(short).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
    }
    /// One tile in the bottom row. A next step's label takes the tint, so it
    /// reads as following the latest answer without a new colour. Next steps
    /// show only while nothing is in progress, so they are never disabled.
    private func rowTile(_ capability: Capability, isNextStep: Bool) -> some View {
        Button { assistant.send(capability.phrase, app: app) } label: {
            if isNextStep {
                tileLabel(capability.shortTitle, symbol: capability.symbol).foregroundStyle(Palette.tint)
            } else {
                tileLabel(capability.shortTitle, symbol: capability.symbol)
            }
        }
        .buttonStyle(TileActionStyle())
        .disabled(assistant.processing)
        .accessibilityLabel(capability.title)
        .accessibilityHint(isNextStep ? "Next step after the latest answer." : "")
        .accessibilityIdentifier(isNextStep ? "assistant-follow-up-\(capability.intent.rawValue)" : "assistant-quick-\(capability.phrase)")
    }
    /// Reads the field's value as Send is tapped; nothing is debounced.
    private func send() {
        guard !assistant.processing else { return }
        let text = input; input = ""; dictation.stop(); focused.wrappedValue = false
        if ["connect apple health", "connect health", "connect healthkit"].contains(text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
            showHealthConnection = true
        } else {
            assistant.send(text, app: app)
        }
    }
}
