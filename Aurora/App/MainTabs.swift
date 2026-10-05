import AuroraCore
import SwiftUI

/// The four tabs in the native tab bar. While the walkthrough is pending,
/// tab selection is locked: the bar ignores taps and the walkthrough moves
/// between tabs itself.
struct MainTabs: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router

    /// What the tab bar shows. The iPad tab bar keeps a refused selection on
    /// screen, so a locked tap is undone by setting this back.
    @State private var shown: AppTab = .summary

    private var walkthroughPending: Bool { model.state.isWalkthroughPending }

    var body: some View {
        @Bindable var router = router
        TabView(selection: $shown) {
            tab(.summary, path: $router.summaryPath) { SummaryView() }
            tab(.sleep, path: $router.sleepPath) { SleepView() }
            tab(.log, path: $router.logPath) { LogView() }
            tab(.insights, path: $router.insightsPath) { InsightsView() }
        }
        .onChange(of: shown) { _, newValue in
            if walkthroughPending {
                if newValue != router.tab { shown = router.tab }
            } else {
                router.tab = newValue
            }
        }
        .onChange(of: router.tab) { _, newValue in
            if shown != newValue { shown = newValue }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if walkthroughPending {
                WalkthroughCoach()
            }
        }
        .sheet(isPresented: $router.showSettings) {
            SettingsView()
        }
        .fullScreenCover(isPresented: $router.showReactionTest) {
            ReactionTestView()
        }
        .onAppear {
            if walkthroughPending {
                router.tab = Walkthrough.tab(forStep: model.state.onboarding.appWalkthroughStep)
            }
            shown = router.tab
        }
    }

    private func tab<Content: View>(
        _ tab: AppTab,
        path: Binding<[HistoryRoute]>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack(path: path) {
            content()
                .navigationDestination(for: HistoryRoute.self) { route in
                    switch route {
                    case .sleep: SleepHistoryView()
                    case .caffeine: CaffeineHistoryView()
                    }
                }
        }
        .tabItem {
            Label(tab.rawValue, systemImage: router.tab == tab ? tab.symbols.selected : tab.symbols.idle)
        }
        .tag(tab)
        .accessibilityIdentifier("tab-\(tab.rawValue)")
    }
}

/// The walkthrough's coach card, pinned above the tab bar. Next saves
/// progress and moves to the next step's tab; Skip or Finish ends the
/// walkthrough for the whole app.
struct WalkthroughCoach: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    @AccessibilityFocusState private var headingFocused: Bool

    var body: some View {
        let index = model.state.onboarding.appWalkthroughStep
        let step = Walkthrough.step(index)
        VStack(alignment: .leading, spacing: Metrics.sm) {
            Text(step.progress)
                .font(.eyebrow)
                .foregroundStyle(Palette.textSecondary)
            Text(step.title)
                .font(.headline)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headingFocused)
            Text(step.body)
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Metrics.sm) {
                Button("Skip") { model.completeWalkthrough() }
                    .buttonStyle(.auroraSecondary)
                    .accessibilityIdentifier("walkthrough-skip")
                Button(step.isLast ? "Finish" : "Next") { advance(from: index) }
                    .buttonStyle(.auroraPrimary)
                    .accessibilityIdentifier("walkthrough-next")
            }
        }
        .padding(Metrics.md)
        .frame(maxWidth: 560)
        .background(RoundedRectangle(cornerRadius: Metrics.heroRadius, style: .continuous).fill(Palette.modalBackground))
        .overlay(RoundedRectangle(cornerRadius: Metrics.heroRadius, style: .continuous).strokeBorder(Palette.cardBorder))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .padding(.horizontal, Metrics.md)
        .padding(.bottom, Metrics.xs)
        .accessibilityElement(children: .contain)
        .onAppear { announce(step) }
        .onChange(of: index) { _, newIndex in announce(Walkthrough.step(newIndex)) }
    }

    private func advance(from index: Int) {
        if Walkthrough.step(index).isLast {
            model.completeWalkthrough()
            return
        }
        model.advanceWalkthrough()
        router.tab = Walkthrough.tab(forStep: model.state.onboarding.appWalkthroughStep)
    }

    private func announce(_ step: Walkthrough.Step) {
        Haptics.selection()
        headingFocused = true
        UIAccessibility.post(notification: .announcement, argument: "\(step.title). \(step.body)")
    }
}
