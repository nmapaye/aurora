import AuroraCore
import EventKit
import SwiftUI
import UIKit

struct AssistantView: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(AssistantModel.self) private var assistant
    @State private var dictation = OnDeviceDictation()
    @State private var input = ""
    @State private var showHealthConnection = false
    /// How far the software keyboard reaches up from the screen's bottom.
    @State private var keyboardOverlap: CGFloat = 0
    /// Messages at least partly on screen, and whether the end is.
    @State private var visibleMessages: Set<UUID> = []
    @State private var endVisible = true
    @State private var viewportHeight: CGFloat = 0
    /// The first message added while earlier messages were being read.
    @State private var heldMessage: UUID?
    @State private var composerWidth: CGFloat = 0
    @FocusState private var composerFocused: Bool
    private static let viewport = "conversation"

    var body: some View {
        @Bindable var assistant = assistant
        @Bindable var router = router
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        identity
                        ForEach(assistant.conversation.messages) { message in
                            messageView(message).id(message.id)
                                .onGeometryChange(for: Bool.self, of: onScreen) { visible in
                                    if visible { visibleMessages.insert(message.id) } else { visibleMessages.remove(message.id) }
                                    if visible && heldMessage == message.id { heldMessage = nil }
                                }
                                .onDisappear { visibleMessages.remove(message.id) }
                        }
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
                            .onGeometryChange(for: Bool.self, of: onScreen) { visible in
                                endVisible = visible
                                if visible { heldMessage = nil }
                            }
                            .onDisappear { endVisible = false }
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
                .coordinateSpace(.named(Self.viewport))
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
                .scrollDismissesKeyboard(.interactively)
                .overlay(alignment: .bottom) { newMessageBelow(proxy) }
                .animation(Motion.content(reduceMotion: reduceMotion), value: heldMessage)
                .onChange(of: assistant.conversation.messages.count) { old, _ in
                    let messages = assistant.conversation.messages
                    let readingLatest = endVisible || (old > 0 && old <= messages.count && visibleMessages.contains(messages[old - 1].id))
                    switch ConversationReveal.after(messages, previousCount: old, readingLatest: readingLatest) {
                    case .none:
                        if messages.isEmpty { heldMessage = nil }
                    case .end:
                        heldMessage = nil
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
            }
            .background(Palette.screen)
            .navigationTitle("Aurora")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 7) {
                        AuroraActivity(active: true, subdued: true).frame(width: 28, height: 20)
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
        }
        .overlay { AuroraEdgeGlow(active: assistant.processing).allowsHitTesting(false).accessibilityHidden(true).ignoresSafeArea() }
        .task { await assistant.start(app: app) }
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
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            keyboardOverlap = Self.keyboardOverlap(note)
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
        .sheet(isPresented: $assistant.showSleepEntry) {
            SleepEntrySheet(mode: .new) { draft in
                app.addManualSleep(draft)
                if app.mutationFailure == nil { assistant.append("Sleep session saved.") }
                else { assistant.failure = app.mutationFailure }
            } onDelete: {}
        }
        .sheet(isPresented: $assistant.showAssistantSettings) { AssistantSettingsView(assistant: assistant) }
        .sheet(isPresented: $showHealthConnection) { HealthConnectionView() }
        .sheet(isPresented: $assistant.showCalendarSettings) { CalendarConnectionsView(service: assistant.calendars) }
        .sheet(item: $assistant.historySheet) { intent in
            if intent == .reactionTest { ReactionTestView() }
            else if intent == .settings { SettingsView() }
            else { AssistantToolsView(destination: intent) }
        }
        .fullScreenCover(isPresented: $router.showReactionTest) { ReactionTestView() }
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
    private func reveal<ID: Hashable>(_ proxy: ScrollViewProxy, _ id: ID, anchor: UnitPoint) {
        Task { @MainActor in
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

    /// The keyboard's end frame against its screen. A hardware keyboard's
    /// offscreen frame gives zero.
    private static func keyboardOverlap(_ note: Notification) -> CGFloat {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return 0 }
        guard let screen = note.object as? UIScreen else { return frame.height }
        return max(0, screen.bounds.maxY - frame.minY)
    }

    private var inputEmpty: Bool { input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Hint, quick actions and composer share the conversation column, so on
    /// iPad they line up with the cards instead of spanning the window.
    private var composer: some View {
        VStack(spacing: Metrics.xs) {
            if !editingCard, !typeSize.isAccessibilitySize, assistant.conversation.messages.filter({ $0.isUser }).count < 3 {
                Text("Start with a quick action, or ask in your own words.")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, Metrics.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .conversationColumn()
            }
            if !editingCard { quickActions }
            HStack(alignment: .bottom, spacing: Metrics.sm) {
                TextField("", text: $input, axis: .vertical)
                    .lineLimit(1...5).focused($composerFocused).accessibilityLabel("Message Aurora").accessibilityIdentifier("assistant-composer")
                    .submitLabel(.send).onSubmit { send() }
                    .frame(minHeight: Metrics.minimumTouchTarget)
                Button {
                    if dictation.recording { dictation.stop() } else { Task { await dictation.start() } }
                } label: { Image(systemName: dictation.recording ? "stop.circle.fill" : "mic").font(.system(size: 20)).frame(width: Metrics.minimumTouchTarget, height: Metrics.minimumTouchTarget) }
                    .accessibilityLabel(dictation.recording ? "Stop local dictation" : "Dictate on device")
                // Send becomes Stop the moment work starts, and back when it ends.
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
            .padding(.horizontal, Metrics.md).padding(.vertical, Metrics.xs)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.heroRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metrics.heroRadius, style: .continuous).strokeBorder(composerFocused ? Palette.tint : Palette.cardBorder))
            // The whole surface focuses the field, not only its text line.
            .contentShape(RoundedRectangle(cornerRadius: Metrics.heroRadius, style: .continuous))
            .onTapGesture { composerFocused = true }
            .conversationColumn()
        }
        .padding(.vertical, Metrics.xs).background(.regularMaterial)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { composerWidth = $0 }
        // The inset never scrolls, so uncapped accessibility sizes left the
        // conversation a sliver of the screen. Messages and cards still scale fully.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
    /// Scrolls past the column's edges, but its first action starts in line
    /// with the cards and composer.
    private var quickActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Metrics.xs) {
                quickAction("Log caffeine", symbol: "cup.and.saucer")
                quickAction("Log sleep", symbol: "moon")
                quickAction("Connect Apple Health", symbol: "heart.text.square") {
                    composerFocused = false
                    showHealthConnection = true
                }
                quickAction("How is my energy?", symbol: "sparkle")
                quickAction("Show my energy curve", symbol: "chart.xyaxis.line")
                quickAction("Check in my energy", symbol: "hand.raised")
                quickAction("Show this week", symbol: "chart.bar")
                quickAction("Review calendar", symbol: "calendar")
                quickAction("Morning briefing", symbol: "sun.horizon")
                quickAction("Reaction test", symbol: "hand.tap")
                quickAction("History", symbol: "clock.arrow.circlepath")
                quickAction("Export records", symbol: "square.and.arrow.up")
                quickAction("Reminders", symbol: "bell")
            }
        }
        .contentMargins(.horizontal, Metrics.columnInset(containerWidth: composerWidth), for: .scrollContent)
        .accessibilityIdentifier("assistant-quick-actions")
    }
    private func quickAction(_ text: String, symbol: String, action: (() -> Void)? = nil) -> some View {
        Button { if let action { action() } else { assistant.send(text, app: app) } } label: {
            Label(text, systemImage: symbol).font(.caption.weight(.medium))
                .padding(.horizontal, Metrics.sm).frame(minHeight: Metrics.minimumTouchTarget)
        }
        .buttonStyle(CapsuleActionStyle()).disabled(assistant.processing).accessibilityIdentifier("assistant-quick-\(text)")
    }
    private func send() {
        guard !assistant.processing else { return }
        let text = input; input = ""; dictation.stop(); composerFocused = false
        if ["connect apple health", "connect health", "connect healthkit"].contains(text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
            showHealthConnection = true
        } else {
            assistant.send(text, app: app)
        }
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
                        NavigationLink("Sleep history", destination: SleepHistoryView())
                        NavigationLink("Sleep trends and Health", destination: SleepView())
                        NavigationLink("Recorded insights", destination: InsightsView())
                        NavigationLink("Records, exports, and privacy", destination: SettingsView())
                    }.navigationTitle("Your records")
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}
