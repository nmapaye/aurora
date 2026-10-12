#if DEBUG
import AuroraCore
import SwiftUI

/// Models for the Design Gallery in their own temporary folder, with a
/// Health provider that refuses every choice, no calendar providers and
/// private defaults. Nothing here can ask for a permission or touch the
/// person's records, calendar selection or notifications.
@MainActor
struct GalleryFixture {
    let app: AppModel
    let assistant: AssistantModel
    let directory: URL

    private static let defaultsSuite = "com.nmapaye.aurora.design-gallery"

    static func make() -> GalleryFixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AuroraGallery-\(UUID().uuidString)")
        // Calendar selection would otherwise be read from and written to the app's own defaults.
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defaults.removePersistentDomain(forName: defaultsSuite)
        let app = AppModel(health: GalleryHealth(), makeStore: { StateStore(directory: directory) }, legacy: { nil })
        let assistant = AssistantModel(calendars: CalendarService(providers: [], defaults: defaults), makeStore: { ConversationStore(directory: directory) })
        return GalleryFixture(app: app, assistant: assistant, directory: directory)
    }

    /// Every later save fails while on: the state file's path becomes a
    /// folder, the same technique as the native failure tests.
    func failSaves(_ on: Bool) {
        let file = directory.appendingPathComponent("state.json")
        try? FileManager.default.removeItem(at: file)
        // Off: the next save writes the file again.
        if on { try? FileManager.default.createDirectory(at: file, withIntermediateDirectories: true) }
    }
}

/// Available, but declares no Health capability, so every choice is refused
/// before HealthKit is asked anything.
struct GalleryHealth: HealthDataProvider {
    var capabilities: HealthCapabilities { [] }
    var isAvailable: Bool { true }
}

/// Setup as people see it, against a fixture: start at a chosen question,
/// make saves fail to see the error, then let them succeed and retry.
struct SetupFixtureView: View {
    enum Start: String, CaseIterable { case name = "Name", health = "Health", finish = "Finish" }
    enum Saving: String, CaseIterable { case works = "Saves work", fails = "Saves fail" }

    @Environment(\.dismiss) private var dismiss
    @State private var fixture = GalleryFixture.make()
    @State private var generation = 0
    @State private var start = Start.name
    @State private var saving = Saving.works

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: Metrics.xs) {
                    Picker("Start at", selection: $start) {
                        ForEach(Start.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("gallery-setup-start")
                    Picker("Saving", selection: $saving) {
                        ForEach(Saving.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("gallery-setup-saving")
                    Text("Synthetic setup in a temporary folder. Health refuses every choice and calendar connections are off.")
                        .font(Typography.source).foregroundStyle(Palette.textSecondary)
                }
                .padding(.horizontal, Metrics.lg).padding(.vertical, Metrics.xs)
                .frame(maxWidth: Metrics.contentMaxWidth)
                SetupConversationView(connectionsEnabled: false)
                    .id(generation)
            }
            .background(Palette.screen)
            .navigationTitle("Setup fixture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("gallery-setup-done")
                }
            }
        }
        .environment(fixture.app).environment(fixture.assistant)
        .task { restart() }
        .onChange(of: start) { _, _ in restart() }
        .onChange(of: saving) { _, value in fixture.failSaves(value == .fails) }
    }

    private func restart() {
        fixture = GalleryFixture.make()
        fixture.app.load()
        switch start {
        case .name: break
        case .health: fixture.app.setSetupStep(.health)
        case .finish: fixture.app.setSetupStep(.finish)
        }
        fixture.failSaves(saving == .fails)
        generation += 1
    }
}

/// The welcome over the conversation, for each kind of evidence it can show.
enum WelcomeFixture: String, CaseIterable, Identifiable {
    case recorded = "Recorded sleep"
    case sample = "Sample Data"
    case none = "No records"
    var id: String { rawValue }

    @MainActor func content() -> WelcomeContent {
        let fixture = GalleryFixture.make()
        let app = fixture.app
        app.load()
        let now = AppModel.currentMillis()
        switch self {
        case .recorded: app.addManualSleep(.init(start: now - 9 * hourMs, end: now - 2 * hourMs, note: "Synthetic fixture"))
        case .sample: app.loadSampleData()
        case .none: break
        }
        app.tick()
        let daypart = Welcome.Daypart.current(clock: app.clock, now: app.now)
        return WelcomeContent(
            daypart: daypart,
            greeting: Welcome.greeting(daypart: daypart, name: nil),
            evidence: Welcome.evidence(state: app.state, now: app.now, clock: app.clock, text: app.text)
        )
    }
}

/// Processing light in each state. Stopped and failed end the same way:
/// the last frame fades out and nothing keeps moving.
struct MotionFixtures: View {
    enum Phase: String, CaseIterable { case rest = "At rest", working = "Working", stopped = "Stopped", failed = "Failed" }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = Phase.rest
    @State private var forceStatic = false

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.sm) {
            Text("Processing light").font(.title2)
            Picker("Processing", selection: $phase) {
                ForEach(Phase.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("gallery-motion-phase")
            Toggle("Static, as with Reduce Motion", isOn: $forceStatic)
            ZStack {
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).fill(Palette.card)
                AuroraEdgeGlow(active: phase == .working, allowsMotion: !forceStatic)
                HStack(spacing: Metrics.sm) {
                    AuroraActivity(active: phase == .working, allowsMotion: !forceStatic).frame(width: 54, height: 36)
                    Text(caption).font(.subheadline).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Metrics.lg)
            }
            .frame(minHeight: 160)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("gallery-motion-preview")
        }
    }

    private var caption: String {
        switch phase {
        case .rest: "No processing light."
        case .working: forceStatic || reduceMotion ? "Working · static light" : "Working · light moves only while work runs"
        case .stopped: "Stopped · last frame fades out"
        case .failed: "Failed · last frame fades out"
        }
    }
}
#endif
