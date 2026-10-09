#if DEBUG
import AuroraCore
import SwiftUI

/// All actions use disposable synthetic state, never the app's record store.
struct DesignGalleryView: View {
    @State private var fixtureApp: AppModel
    @State private var fixtureAssistant: AssistantModel
    @State private var kind = AssistantCard.Kind.caffeineDraft
    /// `nil` follows real interactions (Save, Undo, Discard) in the fixture.
    @State private var state: AssistantCard.State?
    @State private var populated = true
    /// The first conversation message belonging to the current experience.
    @State private var firstMessage = 0
    @State private var showHealthChoices = false
    @State private var healthAtAccessibilitySize = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let kinds: [AssistantCard.Kind] = [.caffeineDraft, .sleepDraft, .energy, .trends, .calendar, .reaction, .history, .exports, .briefing, .reminders, .clarification, .receipt]
    private let states: [AssistantCard.State] = [.ready, .loading, .saved, .undone, .expired, .failed, .discarded]
    private let tones: [(String, StatusTone)] = [("Neutral", .neutral), ("Info", .info), ("Success", .success), ("Warning", .warning), ("Error", .error)]

    init() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AuroraGallery-\(UUID().uuidString)")
        let app = AppModel(health: GalleryHealth(), makeStore: { StateStore(directory: directory) }, legacy: { nil })
        let assistant = AssistantModel(calendars: CalendarService(providers: []), makeStore: { ConversationStore(directory: directory) })
        _fixtureApp = State(initialValue: app)
        _fixtureAssistant = State(initialValue: assistant)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.xl) {
                    Text("Synthetic fixtures only. Native controls, typography, source labels, and accessibility settings use the same renderer as the conversation.")
                        .font(Typography.explanation).foregroundStyle(Palette.textSecondary)
                    Toggle("Populate sample records", isOn: $populated)
                    Picker("Experience", selection: $kind) {
                        ForEach(kinds, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Interaction state", selection: $state) {
                        Text("Live").tag(AssistantCard.State?.none)
                        ForEach(states, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                    }
                    Text("Evidence and actions").font(.title2)
                    ForEach(experience) { message in
                        if let card = message.card { AssistantCardView(message: message, card: display(card)) }
                    }
                    if let failure = fixtureAssistant.failure {
                        Text(failure).font(.footnote).foregroundStyle(Palette.destructive)
                    }
                    healthChoices
                    tokens
                    Text(reduceMotion ? "Reduce Motion: static treatment" : "Motion follows device accessibility settings")
                        .font(Typography.source)
                }
                .padding(Metrics.lg).frame(maxWidth: Metrics.contentMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.screen)
            .navigationTitle("Aurora Design Gallery")
            .accessibilityIdentifier("aurora-design-gallery")
        }
        .environment(fixtureApp).environment(fixtureAssistant).environment(Router())
        .sheet(isPresented: $showHealthChoices) {
            HealthConnectionView()
                .environment(fixtureApp)
                .dynamicTypeSize(healthAtAccessibilitySize ? .accessibility5 : .large)
        }
        .task {
            fixtureApp.load(); fixtureApp.loadSampleData()
            await fixtureAssistant.start(app: fixtureApp)
            await showExperience()
        }
        .onChange(of: kind) { _, _ in Task { await showExperience() } }
        .onChange(of: populated) { _, value in
            if value { fixtureApp.loadSampleData() } else { fixtureApp.deleteAllData() }
            Task { await showExperience() }
        }
        // Mirrors the conversation, which captures the draft as it is edited.
        .onChange(of: fixtureAssistant.pendingDraft) { _, _ in fixtureAssistant.captureDraft(app: fixtureApp) }
        .onChange(of: fixtureAssistant.pendingSleep) { _, _ in fixtureAssistant.captureDraft(app: fixtureApp) }
    }

    /// The draft, its receipt, and any follow-up, so Save → receipt → Undo
    /// can be reviewed as one sequence.
    private var experience: [ConversationMessage] {
        let messages = fixtureAssistant.conversation.messages
        return Array(messages[min(firstMessage, messages.count)...]).filter { $0.card != nil && !$0.isUser }
    }

    /// The Apple Health choices sheet against a fixture provider that never
    /// reaches HealthKit: switches are live, and turning one on is refused.
    private var healthChoices: some View {
        VStack(alignment: .leading, spacing: Metrics.sm) {
            Text("Apple Health choices").font(.title2)
            Toggle("Largest accessibility text", isOn: $healthAtAccessibilitySize)
            Button("Show Health choices") { showHealthChoices = true }
                .buttonStyle(.auroraSecondary)
                .accessibilityIdentifier("gallery-health-choices")
        }
    }

    private var tokens: some View {
        VStack(alignment: .leading, spacing: Metrics.md) {
            Text("Tokens").font(.title2)
            HStack(spacing: Metrics.md) {
                ForEach(Array(Palette.auroraColors.enumerated()), id: \.offset) { _, color in
                    RoundedRectangle(cornerRadius: Metrics.controlRadius).fill(color).frame(height: Metrics.minimumTouchTarget)
                }
            }.accessibilityLabel("Aurora teal, mint, and indigo")
            FlowingBadges(tones: tones)
            VStack(spacing: Metrics.xs) {
                Button("Primary") {}.buttonStyle(.auroraPrimary)
                Button("Primary disabled") {}.buttonStyle(.auroraPrimary).disabled(true)
                Button("Secondary") {}.buttonStyle(.auroraSecondary)
                Button("Secondary disabled") {}.buttonStyle(.auroraSecondary).disabled(true)
            }
            Card {
                LabeledField(label: "Amount", unit: "mg") { Text("120").font(Typography.evidence).monospacedDigit().frame(maxWidth: .infinity, alignment: .leading) }
                Text("Manual · local time").font(Typography.source).foregroundStyle(Palette.textSecondary)
            }
            .accessibilityLabel("Labeled field sample, synthetic value")
        }
    }

    private func display(_ original: AssistantCard) -> AssistantCard {
        guard let state else { return original }
        var card = original; card.state = state
        if state == .failed { card.summary = "Fixture failure. No proposed action was saved." }
        return card
    }

    @MainActor private func showExperience() async {
        fixtureAssistant.failure = nil
        firstMessage = fixtureAssistant.conversation.messages.count
        if kind == .receipt {
            var card = AssistantCard(kind: .receipt, capturedAt: fixtureApp.now, title: "Sample receipt", summary: "Fixture only · no personal record saved")
            card.state = .saved
            card.records = Array(AssistantCards.make(.history, state: fixtureApp.state, now: fixtureApp.now, clock: fixtureApp.clock, text: fixtureApp.text).records.filter { $0.kind == "caffeine" }.prefix(1))
            fixtureAssistant.conversation.messages.append(.init(text: card.summary, card: card))
        } else {
            let card = AssistantCards.make(kind, state: fixtureApp.state, now: fixtureApp.now, clock: fixtureApp.clock, text: fixtureApp.text)
            if let intent = card.refreshIntent {
                await fixtureAssistant.handle(intent, input: "Gallery fixture", app: fixtureApp)
            } else {
                fixtureAssistant.conversation.messages.append(.init(text: card.summary, card: card))
            }
        }
    }
}

/// Available, but declares no Health capability, so every choice is refused
/// before HealthKit is asked anything.
private struct GalleryHealth: HealthDataProvider {
    var capabilities: HealthCapabilities { [] }
    var isAvailable: Bool { true }
}

/// Status badges wrap onto new lines at large text sizes.
private struct FlowingBadges: View {
    let tones: [(String, StatusTone)]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Metrics.xs) { badges }
            VStack(alignment: .leading, spacing: Metrics.xs) { badges }
        }
    }

    private var badges: some View {
        ForEach(tones, id: \.0) { StatusBadge(text: $0.0, tone: $0.1) }
    }
}
#endif
