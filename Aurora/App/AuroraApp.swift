import AuroraCore
import SwiftUI

@main
struct AuroraApp: App {
    @State private var model = AppModel()
    @State private var router = Router()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(router)
                .preferredColorScheme(model.colorScheme)
                .tint(Palette.tint)
                .task { model.load() }
                .onOpenURL { url in
                    guard let link = DeepLink(url: url) else { return }
                    route(link)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await model.foregroundSync() }
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
    }

    private func route(_ link: DeepLink) {
        guard model.phase == .ready else {
            model.pendingLink = link
            return
        }
        let state = model.state
        guard state.onboarding.completed else { return }
        router.open(link.resolved(walkthroughPending: state.isWalkthroughPending, step: state.onboarding.appWalkthroughStep))
    }
}

/// Boot gating: a loading screen while storage opens, recovery when backup
/// exclusion can't be confirmed, first-run setup, then the tabs.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.phase {
        case .loading:
            BootView()
        case .storageUnavailable:
            StorageRecoveryView()
        case .ready:
            if model.state.onboarding.completed {
                MainTabs()
            } else {
                OnboardingView()
            }
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
            Text("Aurora could not protect local records from device backups, so it hasn’t opened them. Nothing was changed or deleted.")
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
