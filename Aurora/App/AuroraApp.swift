import AuroraCore
import SwiftUI

@main
struct AuroraApp: App {
    @State private var model = AppModel()
    @State private var router = Router()
    @State private var purchases = PurchaseService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(router)
                .environment(purchases)
                .preferredColorScheme(model.colorScheme)
                .tint(Palette.tint)
                .task { model.load() }
                .task { await purchases.start() }
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

/// Boot gating: a loading screen while storage opens, recovery when records
/// can't be opened safely, first-run setup, then the tabs.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.phase {
        case .loading:
            BootView()
        case .storageUnavailable:
            StorageRecoveryView(reason: nil)
        case .recovery(let recovery):
            StorageRecoveryView(reason: recovery)
        case .ready:
            Group {
                if model.state.onboarding.completed {
                    MainTabs()
                } else {
                    OnboardingView()
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if model.saveFailed {
                    SaveFailureBanner()
                }
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

/// Shown instead of the app while records can't be opened. Nothing is
/// written from here except an explicit, confirmed fresh start.
struct StorageRecoveryView: View {
    @Environment(AppModel.self) private var model
    /// `nil` when backup exclusion couldn't be confirmed.
    let reason: AppModel.Recovery?
    @State private var confirmFresh = false

    private var copy: (title: String, body: String) {
        switch reason {
        case nil:
            ("Aurora can’t open its records",
             "Aurora could not protect local records from device backups, so it hasn’t opened them. Nothing was changed or deleted.")
        case .unreadable:
            ("Aurora can’t read its records yet",
             "Your records are on this device but couldn’t be read, which can happen before the device is unlocked. Nothing was changed. Unlock the device, then try again.")
        case .corrupt(let backupKept):
            ("Aurora’s saved records are damaged",
             backupKept
                ? "The saved file couldn’t be read. Aurora kept a copy of it and hasn’t changed anything. Try again, or start fresh; the copy stays on this device."
                : "The saved file couldn’t be read, and Aurora couldn’t make a copy of it, so it hasn’t changed anything. Try again.")
        case .legacyUnreadable:
            ("Aurora couldn’t bring over your earlier records",
             "Records from the previous version of Aurora couldn’t be read. They were left exactly as they were, and Aurora will try again each time it opens. You can also start fresh; the earlier records stay on this device.")
        case .importNotSaved:
            ("Aurora couldn’t save your earlier records",
             "Records from the previous version were read but couldn’t be saved. Nothing was changed. Try again.")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.md) {
            Text(copy.title)
                .font(.title2.bold())
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(copy.body)
                .foregroundStyle(Palette.textSecondary)
                .accessibilityIdentifier("storage-recovery-message")
            if model.startFreshFailed {
                Text("Aurora couldn’t start fresh because saving failed. Nothing was changed. Try again.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(StatusTone.error.foreground)
                    .accessibilityIdentifier("storage-start-fresh-failed")
            }
            Button("Try Again") { model.retryStorage() }
                .buttonStyle(.auroraPrimary)
                .accessibilityIdentifier("storage-retry")
            if reason?.allowsStartFresh == true {
                Button("Start Fresh", role: .destructive) { confirmFresh = true }
                    .buttonStyle(.auroraSecondary)
                    .accessibilityIdentifier("storage-start-fresh")
            }
        }
        .padding(Metrics.xl)
        .frame(maxWidth: Metrics.contentMaxWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.screen.ignoresSafeArea())
        .alert("Start with no records?", isPresented: $confirmFresh) {
            Button("Cancel", role: .cancel) {}
            Button("Start Fresh", role: .destructive) { model.startFresh() }
        } message: {
            Text("Aurora will open with no entries. The unreadable data stays on this device and is removed only by Delete All Data.")
        }
    }
}

/// A save didn't reach disk. The change is on screen; Try Again saves it.
struct SaveFailureBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Metrics.sm) {
            Text("Your latest change couldn’t be saved.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(StatusTone.error.foreground)
            Spacer(minLength: 0)
            Button("Try Again") { model.retrySave() }
                .font(.footnote.weight(.semibold))
                .accessibilityIdentifier("save-retry")
        }
        .padding(Metrics.sm)
        .background(StatusTone.error.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("save-failure")
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
