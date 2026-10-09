#if DEBUG
import AuroraCore
import SwiftUI

/// All actions use disposable synthetic state, never the app's record store.
struct DesignGalleryView: View {
    @State private var fixtureApp: AppModel
    @State private var fixtureAssistant: AssistantModel
    @State private var kind = AssistantCard.Kind.energy
    @State private var state = AssistantCard.State.ready
    @State private var populated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let kinds: [AssistantCard.Kind] = [.caffeineDraft, .sleepDraft, .energy, .trends, .calendar, .reaction, .history, .exports, .briefing, .reminders, .clarification, .receipt]
    private let states: [AssistantCard.State] = [.ready, .loading, .saved, .undone, .expired, .failed, .discarded]

    init() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AuroraGallery-\(UUID().uuidString)")
        let app = AppModel(makeStore: { StateStore(directory: directory) }, legacy: { nil })
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
                        ForEach(states, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    HStack(spacing: Metrics.md) {
                        ForEach(Array(Palette.auroraColors.enumerated()), id: \.offset) { _, color in
                            RoundedRectangle(cornerRadius: Metrics.controlRadius).fill(color).frame(height: 44)
                        }
                    }.accessibilityLabel("Aurora teal, mint, and indigo")
                    Text("Evidence and actions").font(.title2)
                    if let message = fixtureAssistant.conversation.messages.last, let card = message.card {
                        AssistantCardView(message: message, card: display(card))
                    }
                    HStack {
                        Button("Primary") {}.buttonStyle(.auroraPrimary)
                        Button("Disabled") {}.buttonStyle(.auroraPrimary).disabled(true)
                    }
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
    }

    private func display(_ original: AssistantCard) -> AssistantCard {
        var card = original; card.state = state
        if state == .failed { card.summary = "Fixture failure. No proposed action was saved." }
        return card
    }

    @MainActor private func showExperience() async {
        if kind == .receipt {
            let card = AssistantCard(kind: .receipt, capturedAt: fixtureApp.now, title: "Sample receipt", summary: "Fixture only · no personal record saved")
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
#endif
