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
    @State private var energyVariant = EnergyVariant.populated
    @State private var healthAtAccessibilitySize = true
    /// Non-energy cards captured three hours earlier, as an old snapshot.
    @State private var earlier = false
    @State private var receiptHealth = ReceiptHealth.none
    @State private var showSetup = false
    @State private var welcome: WelcomeFixture?
    @State private var cutoffFixture = CutoffFixture.feasible
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let kinds: [AssistantCard.Kind] = [.caffeineDraft, .sleepDraft, .energy, .energyProjection, .energyCheckIn, .cutoffScenario, .trends, .calendar, .reaction, .history, .exports, .briefing, .reminders, .clarification, .welcome, .capabilities, .repeatDrink, .receipt]
    private let energyKinds: Set<AssistantCard.Kind> = [.energy, .energyProjection, .energyCheckIn]

    /// Synthetic energy states. Populated and stale use made-up manual
    /// records; sample uses Sample Data; nothing reads personal records.
    enum EnergyVariant: String, CaseIterable {
        case populated, missing, sample, stale, failure, modelUnavailable
        var title: String {
            switch self {
            case .populated: "Populated"
            case .missing: "Missing records"
            case .sample: "Sample Data"
            case .stale: "Earlier snapshot"
            case .failure: "Failed request"
            case .modelUnavailable: "Local model unavailable"
            }
        }
    }
    /// The receipt's Apple Health row, using the app's own status copy.
    enum ReceiptHealth: String, CaseIterable {
        case none = "No Health row", pending = "Export pending", failed = "Not exported", added = "Added", unconfirmed = "Unconfirmed"
        var status: HealthExportStatus? {
            switch self {
            case .none: nil
            case .pending: .pending(.saveCaffeine)
            case .failed: .failed(.saveCaffeine, nil)
            case .added: .exported
            case .unconfirmed: .uncertain
            }
        }
    }
    private let states: [AssistantCard.State] = [.ready, .loading, .saved, .undone, .expired, .failed, .discarded]
    private let tones: [(String, StatusTone)] = [("Neutral", .neutral), ("Info", .info), ("Success", .success), ("Warning", .warning), ("Error", .error)]

    init() {
        let fixture = GalleryFixture.make()
        _fixtureApp = State(initialValue: fixture.app)
        _fixtureAssistant = State(initialValue: fixture.assistant)
        // UI captures preselect with `-AuroraGalleryExperience <kind>` and
        // `-AuroraGalleryCutoff <fixture>`, since a menu that scrolls at the
        // largest text can't be driven reliably.
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: "AuroraGalleryExperience"), let kind = AssistantCard.Kind(rawValue: raw) {
            _kind = State(initialValue: kind)
        }
        if let raw = defaults.string(forKey: "AuroraGalleryCutoff"), let fixture = CutoffFixture(rawValue: raw) {
            _cutoffFixture = State(initialValue: fixture)
        }
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
                    .accessibilityIdentifier("gallery-experience")
                    if energyKinds.contains(kind) {
                        Picker("Energy fixture", selection: $energyVariant) {
                            ForEach(EnergyVariant.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .accessibilityIdentifier("gallery-energy-variant")
                    } else if kind == .cutoffScenario {
                        Picker("Cutoff fixture", selection: $cutoffFixture) {
                            ForEach(CutoffFixture.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .accessibilityIdentifier("gallery-cutoff-variant")
                    } else if kind == .receipt {
                        Picker("Apple Health row", selection: $receiptHealth) {
                            ForEach(ReceiptHealth.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .accessibilityIdentifier("gallery-receipt-health")
                    } else {
                        Toggle("Earlier snapshot (3 hours ago)", isOn: $earlier)
                            .accessibilityIdentifier("gallery-earlier")
                    }
                    Picker("Interaction state", selection: $state) {
                        Text("Live").tag(AssistantCard.State?.none)
                        ForEach(states, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                    }
                    Text("Evidence and actions").font(.title2)
                    ForEach(experience) { message in
                        if let card = message.card {
                            // Its switches reach the real notification center, so they stay off here.
                            AssistantCardView(message: message, card: display(card)).disabled(card.kind == .reminders)
                            if card.kind == .reminders {
                                Text("Fixture: device controls are off; notifications are never requested here.")
                                    .font(Typography.source).foregroundStyle(Palette.textSecondary)
                            }
                        }
                    }
                    if let failure = fixtureAssistant.failure {
                        Text(failure).font(.footnote).foregroundStyle(Palette.destructive)
                    }
                    healthChoices
                    onboarding
                    MotionFixtures()
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
        .sheet(isPresented: $showSetup) { SetupFixtureView() }
        .fullScreenCover(item: $welcome) { variant in
            WelcomeOverlay(content: variant.content(), showing: true) { welcome = nil }
        }
        .onChange(of: kind) { _, _ in Task { await showExperience() } }
        .onChange(of: earlier) { _, _ in Task { await showExperience() } }
        .onChange(of: receiptHealth) { _, _ in Task { await showExperience() } }
        .onChange(of: energyVariant) { _, _ in Task { await showExperience() } }
        .onChange(of: cutoffFixture) { _, _ in Task { await showExperience() } }
        .onChange(of: populated) { _, value in
            if value { fixtureApp.loadSampleData() } else { fixtureApp.deleteAllData() }
            Task { await showExperience() }
        }
        // Writes the draft into its card as it is edited, so closed states can
        // be reviewed here; the conversation writes it only when the draft closes.
        .onChange(of: fixtureAssistant.pendingDraft) { _, _ in fixtureAssistant.captureDraft(app: fixtureApp) }
        .onChange(of: fixtureAssistant.pendingSleep) { _, _ in fixtureAssistant.captureDraft(app: fixtureApp) }
        .onChange(of: fixtureAssistant.pendingCheckIn) { _, _ in fixtureAssistant.captureDraft(app: fixtureApp) }
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

    /// Setup with failing and working saves, and the welcome for each kind of evidence.
    private var onboarding: some View {
        VStack(alignment: .leading, spacing: Metrics.sm) {
            Text("First run").font(.title2)
            Button("Show setup fixture") { showSetup = true }
                .buttonStyle(.auroraSecondary)
                .accessibilityIdentifier("gallery-setup")
            ForEach(WelcomeFixture.allCases) { variant in
                Button("Welcome · \(variant.rawValue)") { welcome = variant }
                    .buttonStyle(.auroraSecondary)
                    .accessibilityIdentifier("gallery-welcome-\(variant)")
            }
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
        if energyKinds.contains(kind) {
            await showEnergy()
        } else if kind == .cutoffScenario {
            await cutoffFixture.show(app: fixtureApp, assistant: fixtureAssistant)
        } else if kind == .calendar {
            // Made-up events from both sources; the shared standup appears once.
            fixtureApp.tick()
            var card = AssistantCard(kind: .calendar, capturedAt: fixtureApp.now, title: "Your commitments", summary: "")
            card.timeZone = fixtureApp.clock.timeZone.identifier
            card.commitments = CalendarMerge.newestCopies(Self.calendarFixtures(now: Date(timeIntervalSince1970: fixtureApp.now / 1000)))
            fixtureAssistant.conversation.messages.append(.init(text: card.title, card: card))
        } else if kind == .repeatDrink {
            // A made-up Drip at 9:30 yesterday; nothing reads personal records.
            fixtureApp.tick()
            let yesterday = fixtureApp.clock.addingDays(-1, to: fixtureApp.clock.setTime(fixtureApp.now, hour: 9, minute: 30))
            let prompt = RepeatDrinks.Prompt(doseID: "gallery-fixture", source: "Drip", mg: 95, yesterdayAt: yesterday, dueAt: fixtureApp.clock.addingDays(1, to: yesterday) + RepeatDrinks.followUpDelayMs)
            var card = AssistantCard(kind: .repeatDrink, capturedAt: fixtureApp.now, title: RepeatDrinks.question(prompt, text: fixtureApp.text), summary: RepeatDrinks.detail(prompt))
            card.timeZone = fixtureApp.clock.timeZone.identifier
            card.repeatDrink = prompt
            let message = ConversationMessage(text: card.title, intent: .logCaffeine, suggestionKey: prompt.id, card: card)
            fixtureAssistant.conversation.messages.append(message)
            fixtureAssistant.activeCards.insert(message.id)
        } else if kind == .receipt {
            var card = AssistantCard(kind: .receipt, capturedAt: fixtureApp.now, title: "Sample receipt", summary: "Fixture only · no personal record saved")
            card.state = .saved
            card.records = Array(AssistantCards.make(.history, state: fixtureApp.state, now: fixtureApp.now, clock: fixtureApp.clock, text: fixtureApp.text).records.filter { $0.kind == "caffeine" }.prefix(1))
            if let status = receiptHealth.status, let row = AssistantModel.healthMetric(status) { card.metrics = [row] }
            fixtureAssistant.conversation.messages.append(.init(text: card.summary, card: card))
        } else if earlier {
            fixtureApp.tick()
            var card = AssistantCards.make(kind, state: fixtureApp.state, now: fixtureApp.now - 3 * hourMs, clock: fixtureApp.clock, text: fixtureApp.text)
            card.timeZone = fixtureApp.clock.timeZone.identifier
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

extension DesignGalleryView {
    @MainActor private func showEnergy() async {
        fixtureApp.deleteAllData()
        switch energyVariant {
        case .sample: fixtureApp.loadSampleData()
        case .missing, .modelUnavailable: break
        case .populated, .stale, .failure: seedSyntheticEnergyRecords()
        }
        fixtureApp.tick()
        let now = fixtureApp.now
        let current = AssistantCards.make(kind, state: fixtureApp.state, now: now, clock: fixtureApp.clock, text: fixtureApp.text)
        switch energyVariant {
        case .stale:
            // Captured three hours earlier from the records known then.
            let card = AssistantCards.make(kind, state: fixtureApp.state, now: now - 3 * hourMs, clock: fixtureApp.clock, text: fixtureApp.text)
            fixtureAssistant.conversation.messages.append(.init(text: card.title, card: card))
        case .failure:
            var card = AssistantCard(kind: kind, capturedAt: now, title: current.title, summary: "This request didn't finish. Refresh for a current result.")
            card.state = .failed; card.timeZone = fixtureApp.clock.timeZone.identifier
            fixtureAssistant.conversation.messages.append(.init(text: card.summary, card: card))
        case .modelUnavailable:
            fixtureAssistant.failure = IntelligenceFailure.unavailable.errorDescription
            let card = AssistantCards.make(.clarification, state: fixtureApp.state, now: now, clock: fixtureApp.clock, text: fixtureApp.text)
            fixtureAssistant.conversation.messages.append(.init(text: card.summary, card: card))
        case .populated, .missing, .sample:
            if let intent = current.refreshIntent {
                await fixtureAssistant.handle(intent, input: "Gallery fixture", app: fixtureApp)
            }
        }
    }

    static func calendarFixtures(now: Date) -> [Commitment] {
        let day = Calendar.current.startOfDay(for: now)
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            Calendar.current.date(byAdding: DateComponents(day: dayOffset, hour: hour, minute: minute), to: day)!
        }
        func event(_ id: String, _ provider: CalendarProviderID, _ title: String, _ start: Date, minutes: Double, color: String, location: String? = nil, modified: TimeInterval = 0, allDay: Bool = false) -> Commitment {
            Commitment(id: id, calendarID: "fixture-\(provider.rawValue)", provider: provider, title: title, start: start, end: start.addingTimeInterval(minutes * 60),
                       timeZone: TimeZone.current.identifier, revision: "fixture", canMove: false, recurring: false,
                       location: location, colorHex: color, lastModified: now.addingTimeInterval(modified), allDay: allDay)
        }
        return [
            event("g1", .google, "Team standup", at(0, 9, 30), minutes: 15, color: "#039BE5", location: "Meet", modified: -60),
            event("a1", .apple, "Team standup", at(0, 9, 30), minutes: 15, color: "#34C759", modified: -3600),
            event("a2", .apple, "Dentist", at(0, 14), minutes: 45, color: "#FF9500", location: "12 Main St"),
            event("g2", .google, "Design review", at(0, 16), minutes: 60, color: "#7986CB"),
            event("a3", .apple, "Gym", at(1, 7), minutes: 60, color: "#34C759"),
            event("g3", .google, "Lunch with Alex", at(1, 12, 30), minutes: 60, color: "#F6BF26", location: "Café Luna"),
        ]
    }

    /// Made-up manual records for the populated and stale fixtures.
    @MainActor private func seedSyntheticEnergyRecords() {
        let now = AppModel.currentMillis()
        fixtureApp.addManualSleep(.init(start: now - 11 * hourMs, end: now - 4 * hourMs, note: "Synthetic fixture"))
        _ = fixtureApp.addCustomDose(.init(mg: "95", source: "Drip", timestamp: now - 3 * hourMs, note: "Synthetic fixture"))
        _ = fixtureApp.addCustomDose(.init(mg: "60", source: "Tea", timestamp: now - 90 * minuteMs, note: "Synthetic fixture"))
        fixtureApp.addEnergyCheckIn(.init(id: RecordID.newEnergyCheckInID(now: now - hourMs), recordedAt: now - hourMs, rating: 3, note: "Synthetic fixture"))
    }
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
