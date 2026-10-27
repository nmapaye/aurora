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
        /// The person is dragging or flinging the conversation (iOS 18 and
        /// later). Only their own scrolling changes where they are reading;
        /// Aurora revealing a long card's start doesn't move them away from
        /// the latest message.
        var userScrolling = false
        /// What a taller bottom area keeps in view (`ConversationFollow`).
        var follow = ConversationFollow()
        var revealTask: Task<Void, Never>?
    }
    @State private var viewportHeight: CGFloat = 0
    /// The first message added while earlier messages were being read.
    @State private var heldMessage: UUID?
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
                        ForEach(shownMessages) { message in conversationRow(message) }
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
                                visibility.end = visible
                                if visible { visibility.follow.stopFollowing() }
                                if visible && heldMessage != nil { heldMessage = nil }
                            }
                            .onDisappear { visibility.end = false }
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
                // Opens at the latest message, including right after the welcome.
                // Scrolled once rather than with defaultScrollAnchor(.bottom): on
                // iOS 26.5 that anchor, with the lazy stack's estimated heights,
                // kept the conversation re-laying out so the main thread never
                // went idle.
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
                .onDisappear { visibility.revealTask?.cancel() }
                .coordinateSpace(.named(Self.viewport))
                .trackingConversationEnd(visibility, layoutChanged: { old, new in
                    guard !visibility.userScrolling,
                          case .start(let id) = visibility.follow.afterLayoutChanged(
                            from: old, to: new, latestMessage: assistant.conversation.messages.last?.id,
                            holding: heldMessage != nil)
                    else { return }
                    reveal(proxy, id, anchor: .top)
                }) { end, nearEnd in
                    if visibility.userScrolling || end {
                        visibility.end = end
                        visibility.nearEnd = nearEnd || end
                    }
                    if end && heldMessage != nil { heldMessage = nil }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if viewportHeight != $0 { viewportHeight = $0 } }
                .scrollDismissesKeyboard(.interactively)
                .overlay(alignment: .bottom) { newMessageBelow(proxy) }
                .animation(Motion.content(reduceMotion: reduceMotion), value: heldMessage)
                // A taller bottom area would otherwise cover what the person
                // was reading: the end, or the start of the reply just revealed.
                .onChange(of: composerHeight) { old, new in
                    switch visibility.follow.afterBottomAreaGrew(from: old, to: new, atEnd: visibility.end, holding: heldMessage != nil) {
                    case .start(let id): reveal(proxy, id, anchor: .top)
                    case .end: reveal(proxy, "bottom", anchor: .bottom)
                    case .none, .hold: break
                    }
                }
                // Dismissing the keyboard can shift a revealed title under
                // the bar without changing the composer's measured height.
                // Wait for UIKit's completion rather than guessing a delay.
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                    guard !visibility.userScrolling,
                          case .start(let id) = visibility.follow.afterKeyboardDismissed(
                            latestMessage: assistant.conversation.messages.last?.id, holding: heldMessage != nil)
                    else { return }
                    reveal(proxy, id, anchor: .top)
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
                        .accessibilityLabel("History and native tools").accessibilityIdentifier("assistant-history")
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
        let readingLatest = visibility.end || visibility.nearEnd || (old > 0 && old <= messages.count && visibility.messages.contains(messages[old - 1].id))
        windowStart = ConversationWindow.start(windowStart, count: messages.count, previousCount: old)
        let next = ConversationReveal.after(messages, previousCount: old, readingLatest: readingLatest)
        visibility.follow.revealed(next)
        switch next {
        case .none:
            if messages.isEmpty { heldMessage = nil }
        case .end:
            // Going to the end anyway: drop revealed earlier messages so
            // the plain stack doesn't grow without bound.
            heldMessage = nil; windowStart = nil
            reveal(proxy, "bottom", anchor: .bottom)
        case .start(let id):
            heldMessage = nil
            reveal(proxy, id, anchor: .top)
        case .hold(let id):
            // Keep the earliest unseen message; reading resumes there.
            if heldMessage == nil {
                heldMessage = id
                UIAccessibility.post(notification: .announcement, argument: "New message below")
            }
        }
    }

    /// The messages the stack renders: the latest, plus any earlier batches
    /// the person asked for. Every reveal target is among the newest.
    private var shownMessages: ArraySlice<ConversationMessage> {
        let messages = assistant.conversation.messages
        return messages[ConversationWindow.first(windowStart, count: messages.count)...]
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

    @ViewBuilder private var identity: some View {
        if !assistant.conversation.messages.contains(where: \.isUser) {
            VStack(alignment: .leading, spacing: 6) {
                Text("A little clarity for your day.").font(.title2.weight(.medium))
                Text(assistant.intelligenceName).font(.caption).foregroundStyle(Palette.textSecondary)
                if app.state.demoMode { Text("Sample Data · for exploration").font(.caption).foregroundStyle(Palette.caffeineAccent) }
            }.padding(.vertical, 6)
        }
    }
    private func startsGroup(_ message: ConversationMessage) -> Bool {
        guard let index = assistant.conversation.messages.firstIndex(where: { $0.id == message.id }), index > 0 else { return true }
        return message.createdAt.timeIntervalSince(assistant.conversation.messages[index - 1].createdAt) > 300
    }
    @ViewBuilder private func messageView(_ message: ConversationMessage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if startsGroup(message) {
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
        visibility.revealTask?.cancel()
        visibility.revealTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(Motion.content(reduceMotion: reduceMotion)) { proxy.scrollTo(id, anchor: anchor) }
        }
    }

    @ViewBuilder private func newMessageBelow(_ proxy: ScrollViewProxy) -> some View {
        if let held = heldMessage {
            Button {
                heldMessage = nil
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
    private func conversationRow(_ message: ConversationMessage) -> some View {
        messageView(message)
        .id(message.id)
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

struct AssistantToolsView: View {
    let destination: AssistantIntent
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if destination == .logSleep { SleepHistoryView() }
                else if destination == .logCaffeine { CaffeineHistoryView() }
                else {
                    List {
                        NavigationLink("Caffeine history", destination: CaffeineHistoryView())
                        // Sleep's own "All sleep entries" holds the full list.
                        NavigationLink("Sleep", destination: SleepView())
                        NavigationLink("Recorded insights", destination: InsightsView())
                        NavigationLink("Records, exports, and privacy", destination: SettingsView(pushed: true))
                    }.navigationTitle("Your records")
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
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
    /// end of the conversation is on screen, and whether it is within most of
    /// a screen of it (still reading the latest message).
    @ViewBuilder
    func trackingConversationEnd(_ visibility: AssistantView.Visibility,
                                 layoutChanged: @escaping (ConversationLayout, ConversationLayout) -> Void,
                                 _ action: @escaping (_ end: Bool, _ nearEnd: Bool) -> Void) -> some View {
        if #available(iOS 18, *) {
            onScrollPhaseChange { _, phase in
                visibility.userScrolling = phase == .interacting || phase == .decelerating
                if visibility.userScrolling {
                    visibility.follow.stopFollowing()
                    visibility.revealTask?.cancel()
                }
            }
            .onScrollGeometryChange(for: ConversationEnd.self) { geometry in
                let maxOffset = geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom - geometry.containerSize.height
                let gap = max(0, maxOffset - geometry.contentOffset.y - geometry.contentInsets.top)
                return ConversationEnd(end: gap <= 24, nearEnd: gap < geometry.containerSize.height * 0.75,
                    layout: ConversationLayout(container: geometry.containerSize,
                        contentHeight: geometry.contentSize.height, topInset: geometry.contentInsets.top,
                        bottomInset: geometry.contentInsets.bottom))
            } action: { old, now in
                action(now.end, now.nearEnd)
                layoutChanged(old.layout, now.layout)
            }
        } else {
            self
        }
    }
}

private struct ConversationEnd: Equatable {
    var end: Bool
    var nearEnd: Bool
    var layout: ConversationLayout
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
            .onChange(of: phase) { _, value in
                if value != .active { dictation.stop(); assistant.releaseWarmResources(); assistant.clearCardFocus() }
            }
            .onChange(of: assistant.pendingDraft) { _, _ in assistant.captureDraft(app: app) }
            .onChange(of: assistant.pendingSleep) { _, _ in assistant.captureDraft(app: app) }
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
            if !editingCard, !typeSize.isAccessibilitySize, assistant.conversation.messages.filter({ $0.isUser }).count < 3 {
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
