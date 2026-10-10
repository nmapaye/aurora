import AuroraCore
import EventKit
import SwiftUI

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
    @FocusState private var composerFocused: Bool

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
                        }
                        if assistant.processing {
                            HStack(spacing: 12) {
                                AuroraActivity(active: true).frame(width: 54, height: 36)
                                Text(assistant.status).font(.subheadline).foregroundStyle(Palette.textSecondary)
                                Spacer()
                                Button("Stop") { assistant.cancel() }.accessibilityIdentifier("assistant-stop")
                            }
                            .accessibilityElement(children: .contain)
                        }
                        if let failure = assistant.failure ?? dictation.error {
                            Text(failure).foregroundStyle(Palette.destructive).font(.footnote)
                                .accessibilityIdentifier("assistant-error")
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .frame(maxWidth: Metrics.contentMaxWidth).frame(maxWidth: .infinity)
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: assistant.conversation.messages.count) { _, _ in
                    if reduceMotion { proxy.scrollTo("bottom", anchor: .bottom) }
                    else { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) } }
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
            if value != .active { dictation.stop(); assistant.releaseWarmResources(); assistant.editingCardField = false }
        }
        .onChange(of: assistant.pendingDraft) { _, _ in assistant.captureDraft(app: app) }
        .onChange(of: assistant.pendingSleep) { _, _ in assistant.captureDraft(app: app) }
        .onChange(of: app.state.vigilanceSessions) { old, new in
            if assistant.historySheet == .reactionTest, new.contains(where: { record in !RecordID.isSample(record.id) && !old.contains(where: { $0.id == record.id }) }) { assistant.reactionCompleted(app: app) }
        }
        .onChange(of: app.state.sleeps) { old, _ in assistant.sleepChanged(app: app, before: old) }
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

    /// While a card's own field is being edited, the inset rides above the
    /// keyboard. Keep only the composer field so the card's Save stays
    /// visible and swipes can't land on quick actions.
    private var editingCard: Bool { assistant.editingCardField && !composerFocused }

    private var composer: some View {
        VStack(spacing: 10) {
            if !editingCard, !typeSize.isAccessibilitySize, assistant.conversation.messages.filter({ $0.isUser }).count < 3 {
                Text("Start with a quick action, or ask in your own words.")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, 16)
            }
            if !editingCard { quickActions }
            HStack(alignment: .center, spacing: 12) {
                TextField("", text: $input, axis: .vertical)
                    .lineLimit(1...5).focused($composerFocused).accessibilityLabel("Message Aurora").accessibilityIdentifier("assistant-composer")
                    .submitLabel(.send).onSubmit { send() }
                Button {
                    if dictation.recording { dictation.stop() } else { Task { await dictation.start() } }
                } label: { Image(systemName: dictation.recording ? "stop.circle.fill" : "mic").font(.system(size: 20)).frame(width: 44, height: 44) }
                    .accessibilityLabel(dictation.recording ? "Stop local dictation" : "Dictate on device")
                Button(action: send) {
                    Image(systemName: "arrow.up").font(.system(size: 20, weight: .semibold)).frame(width: 44, height: 44)
                        .background(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || assistant.processing ? Palette.primaryButtonDisabled : Palette.tint, in: Circle())
                        .foregroundStyle(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || assistant.processing ? Palette.primaryButtonDisabledText : Palette.primaryButtonText)
                }
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || assistant.processing)
                    .accessibilityLabel("Send to Aurora").accessibilityIdentifier("assistant-send")
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(Palette.cardBorder))
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 10).background(.regularMaterial)
        // The inset never scrolls, so uncapped accessibility sizes left the
        // conversation a sliver of the screen. Messages and cards still scale fully.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
    private var quickActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
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
            .padding(.horizontal, 16)
        }
        .accessibilityIdentifier("assistant-quick-actions")
    }
    private func quickAction(_ text: String, symbol: String, action: (() -> Void)? = nil) -> some View {
        Button { if let action { action() } else { assistant.send(text, app: app) } } label: { Label(text, systemImage: symbol).font(.caption.weight(.medium)).padding(12).frame(minHeight: 44).background(Palette.card, in: Capsule()) }
            .buttonStyle(.plain).disabled(assistant.processing).accessibilityIdentifier("assistant-quick-\(text)")
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

/// A small identity at rest; a brighter ribbon accompanies actual processing.
struct AuroraActivity: View {
    let active: Bool
    var subdued = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        if active && !reduceMotion && scenePhase == .active {
            TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
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
