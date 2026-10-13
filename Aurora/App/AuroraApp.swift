import AuroraCore
import SwiftUI

@main
struct AuroraApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private var model: AppModel { delegate.model }
    @State private var router = Router()
    @State private var assistant = AssistantModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-AuroraDesignGallery") { DesignGalleryView() } else { RootView() }
                    #else
                    RootView()
                    #endif
                }
                .environment(model)
                .environment(router)
                .environment(assistant)
                .preferredColorScheme(model.colorScheme)
                .tint(Palette.tint)
                .task {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-AuroraDesignGallery") { return }
                    #endif
                    connectAssistant()
                    Signposts.event("Launch.SceneTask")
                    model.load()
                }
                .onOpenURL { url in
                    guard let link = DeepLink(url: url) else { return }
                    route(link)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await model.foregroundSync() }
                    } else if phase == .background {
                        BackgroundRefresh.schedule(enabled: backgroundRefreshWanted)
                    }
                }
                .task(id: model.phase) {
                    guard model.phase == .ready else { return }
                    if let link = model.pendingLink {
                        model.pendingLink = nil
                        route(link)
                    }
                    await model.foregroundSync()
                    // Keep "now" moving so the day rolls over at midnight.
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(60))
                        model.tick()
                    }
                }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await refreshAssistantInBackground()
        }
    }

    /// A granted opportunity runs the same coalesced refresh as foreground:
    /// Health reads that were chosen, then calendars and suggestions under
    /// the existing opt-in limits.
    @MainActor private func refreshAssistantInBackground() async {
        connectAssistant()
        model.load()
        guard model.phase == .ready, model.state.onboarding.completed else { return }
        await assistant.start(app: model)
        guard !Task.isCancelled else { return }
        await model.refresh(.background)
        BackgroundRefresh.schedule(enabled: backgroundRefreshWanted)
    }

    /// Calendars, suggestions and sleep-change offers run through the
    /// assistant, which applies its opt-in policy.
    @MainActor private func connectAssistant() {
        model.assistantRefresh = { [assistant, model] steps in
            await assistant.foreground(app: model, steps: steps)
        }
        model.sleepChanged = { [assistant, model] before in
            assistant.sleepChanged(app: model, before: before)
        }
    }

    /// Only opted-in suggestions or a chosen Health read ask iOS for time.
    @MainActor private var backgroundRefreshWanted: Bool {
        assistant.conversation.preferences.proactive || !model.state.healthChoices.observedKinds.isEmpty
    }

    private func route(_ link: DeepLink) {
        guard model.phase == .ready else {
            model.pendingLink = link
            return
        }
        let state = model.state
        guard state.onboarding.completed else { return }
        router.open(link)
    }
}

/// Boot gating: a loading screen while storage opens, recovery when backup
/// exclusion can't be confirmed, first-run setup, then the conversation with
/// a once-per-launch welcome over it.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Set when storage first opens, so the welcome plays at most once per
    /// launch and never right after finishing setup or an erase.
    @State private var launchHandled = false
    @State private var welcome = Welcome.Presentation.atLaunch(onboardingCompleted: false, voiceOverRunning: false)
    /// Kept while the welcome fades after a skip; it no longer takes touches.
    @State private var welcomeContent: WelcomeContent?

    var body: some View {
        switch model.phase {
        case .loading:
            BootView().onAppear { Signposts.event("Launch.BootVisible") }
        case .storageUnavailable:
            StorageRecoveryView().onAppear { Signposts.event("Launch.RecoveryVisible") }
        case .ready:
            Group {
                if model.state.onboarding.completed {
                    AssistantView()
                        .onAppear { Signposts.event("Launch.AssistantVisible") }
                        .accessibilityHidden(welcome.hidesConversationFromAccessibility)
                        .overlay {
                            if let welcomeContent {
                                WelcomeOverlay(content: welcomeContent, showing: welcome.showing, onSkip: skipWelcome)
                                    .opacity(welcome.showing ? 1 : 0)
                                    .allowsHitTesting(welcome.blocksInteraction)
                                    .accessibilityHidden(!welcome.showing)
                            }
                        }
                } else {
                    OnboardingView().onAppear { Signposts.event("Launch.OnboardingVisible") }
                }
            }
            .onAppear(perform: handleLaunch)
            .onChange(of: model.state.onboarding.completed) { _, completed in
                // Run what an activation would, so Health reads chosen during
                // setup start now instead of at the next foreground.
                if completed { Task { await model.foregroundSync() } }
            }
        }
    }

    private func handleLaunch() {
        guard !launchHandled else { return }
        launchHandled = true
        let presentation = Welcome.Presentation.atLaunch(
            onboardingCompleted: FirstRun(model.state.onboarding) == .done,
            voiceOverRunning: UIAccessibility.isVoiceOverRunning
        )
        guard presentation.showing else { return }
        model.tick()
        let daypart = Welcome.Daypart.current(clock: model.clock, now: model.now)
        welcomeContent = WelcomeContent(
            daypart: daypart,
            greeting: Welcome.greeting(daypart: daypart, name: model.state.prefs.displayName),
            evidence: Welcome.evidence(state: model.state, now: model.now, clock: model.clock, text: model.text)
        )
        welcome = presentation
    }

    /// Touches and VoiceOver return to the conversation in this update; the
    /// fade that follows ignores touches.
    private func skipWelcome() {
        guard welcome.showing else { return }
        if reduceMotion {
            welcome.skip()
            welcomeContent = nil
            return
        }
        // The exit (card lifting away, mark swelling) is decoration over a
        // conversation that is already usable.
        withAnimation(.easeIn(duration: 0.7)) {
            welcome.skip()
        } completion: {
            if !welcome.showing { welcomeContent = nil }
        }
    }
}

struct BootView: View {
    var body: some View {
        VStack(spacing: Metrics.md) {
            AuroraMark()
                .frame(width: 72, height: 72)
            Text("Loading Aurora…")
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.screen.ignoresSafeArea())
        .accessibilityElement(children: .combine)
    }
}

struct StorageRecoveryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.md) {
            Text("Aurora can’t open its records")
                .font(.title2.bold())
                .foregroundStyle(Palette.textPrimary)
            Text(model.mutationFailure ?? "Aurora could not open or verify its protected local records. The original files are preserved. Retry after restoring access or recovering the saved file.")
                .foregroundStyle(Palette.textSecondary)
            Button("Retry opening AURORA") { model.retryStorage() }
                .buttonStyle(.auroraPrimary)
        }
        .padding(Metrics.xl)
        .frame(maxWidth: Metrics.contentMaxWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.screen.ignoresSafeArea())
    }
}

/// The Aurora wave mark: a ribbon that crests once and rises, with a dot
/// above the horizon.
struct AuroraMark: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 128
            var wave = Path()
            wave.move(to: CGPoint(x: 30, y: 84))
            wave.addCurve(to: CGPoint(x: 74, y: 82), control1: CGPoint(x: 46, y: 48), control2: CGPoint(x: 60, y: 48))
            wave.addCurve(to: CGPoint(x: 102, y: 56), control1: CGPoint(x: 82, y: 62), control2: CGPoint(x: 92, y: 54))
            let transform = CGAffineTransform(scaleX: scale, y: scale)
            context.stroke(
                wave.applying(transform),
                with: .color(Palette.tint),
                style: StrokeStyle(lineWidth: 13 * scale, lineCap: .round, lineJoin: .round)
            )
            let dot = Path(ellipseIn: CGRect(x: 27, y: 29, width: 18, height: 18)).applying(transform)
            context.fill(dot, with: .color(Palette.tint))
        }
        .accessibilityHidden(true)
    }
}
