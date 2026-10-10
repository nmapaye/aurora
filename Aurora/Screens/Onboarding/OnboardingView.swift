import AuroraCore
import SwiftUI

/// First run: three skippable "Your day as a sky" scenes, then setup as a
/// short conversation. A relaunch mid-setup skips the scenes and resumes at
/// the next unanswered question.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if case .setup = FirstRun(model.state.onboarding) {
                SetupConversationView()
                    .transition(.opacity)
            } else {
                StoryScenesView {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: Motion.contentDuration)) {
                        model.setSetupStep(.name)
                    }
                }
                .transition(.opacity)
            }
        }
    }
}

/// Dawn, midday light, dusk. Swipe or Continue; Skip is always available
/// and goes straight to setup. The sky changes with the scene.
struct StoryScenesView: View {
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0

    private let scenes = SetupCopy.scenes

    var body: some View {
        let scene = scenes[page]
        ZStack {
            AuroraSky(daypart: scene.daypart)
                .id(scene.daypart)
                .transition(.opacity)
            VStack(spacing: 0) {
                HStack {
                    AuroraMark().frame(width: 32, height: 32)
                    Spacer()
                    Button("Skip", action: onFinish)
                        .font(.body.weight(.medium))
                        .frame(minWidth: Metrics.minimumTouchTarget, minHeight: Metrics.minimumTouchTarget)
                        .accessibilityHint("Goes to setup.")
                        .accessibilityIdentifier("onboarding-skip-story")
                }
                .padding(.horizontal, Metrics.lg)
                TabView(selection: $page) {
                    ForEach(scenes) { scene in
                        sceneCard(scene).tag(scene.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .interactive))
                Button(page == scenes.count - 1 ? "Begin setup" : "Continue") {
                    if page == scenes.count - 1 { onFinish() } else { page += 1 }
                }
                .buttonStyle(.auroraPrimary)
                .padding(.horizontal, Metrics.lg)
                .padding(.bottom, Metrics.md)
                .frame(maxWidth: Metrics.contentMaxWidth)
                .accessibilityIdentifier("story-continue")
            }
        }
        .background(Palette.screen.ignoresSafeArea())
        .animation(reduceMotion ? nil : .easeInOut(duration: Motion.contentDuration), value: page)
        .onChange(of: page) { _, _ in Haptics.selection() }
    }

    private func sceneCard(_ scene: SetupCopy.Scene) -> some View {
        GeometryReader { proxy in
            ScrollView {
                VStack {
                    Spacer(minLength: Metrics.md)
                    sceneText(scene)
                }
                // Sits at the bottom of the page, and scrolls once large text
                // makes it taller than the page.
                .frame(minHeight: proxy.size.height, alignment: .bottom)
                .padding(.horizontal, Metrics.lg)
                .frame(maxWidth: Metrics.contentMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            // Large text: open at the headline, not the end of the body.
            .defaultScrollAnchor(.top)
        }
        // Clears the page indicator below the card.
        .padding(.bottom, Metrics.xxl + Metrics.lg)
    }

    private func sceneText(_ scene: SetupCopy.Scene) -> some View {
        VStack(alignment: .leading, spacing: Metrics.sm) {
            Text("\(scene.eyebrow) · \(scene.id + 1) of \(scenes.count)")
                .font(.eyebrow)
                .foregroundStyle(Palette.textSecondary)
            Text(scene.title)
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(scene.body)
                .font(.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metrics.xl)
        .auroraGlass()
        .accessibilityElement(children: .combine)
    }
}

/// Lets a view pick between two button styles at run time.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
    }
}
