import AuroraCore
import SwiftUI

/// First-run setup as a short conversation. Aurora asks one question at a
/// time; every question can be skipped, and "Skip to the end" leaves setup
/// at any point. Each answer is saved as it is given, so a relaunch resumes
/// at the next question. Health and calendars use the same connection
/// services as Settings, and nothing is requested until the person chooses
/// it here. Health access is never shown as granted.
struct SetupConversationView: View {
    @Environment(AppModel.self) private var model
    @Environment(AssistantModel.self) private var assistant
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var controlsHeight: CGFloat = 0
    @State private var name = ""
    @State private var working: HealthChoice?
    @State private var healthMessages: [HealthChoice: String] = [:]
    @State private var showCalendars = false
    @FocusState private var nameFocused: Bool

    /// The choices that ask Health for a permission. Background updates stay
    /// in Apple Health settings.
    private static let healthChoices: [HealthChoice] = [.readSleep, .readCaffeine, .writeCaffeine]

    private var step: SetupStep { SetupStep(stored: model.state.onboarding.setupStep) }
    private var modelAvailable: Bool { AppleIntentModel.available }

    var body: some View {
        ZStack {
            AuroraSky(daypart: .evening, animating: false)
                .opacity(0.55)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Metrics.md) {
                        HStack {
                            AuroraMark().frame(width: 40, height: 40)
                            Spacer()
                            if step != .finish {
                                Button("Skip to the end") { leave(to: .finish) }
                                    .font(.subheadline.weight(.medium))
                                    .frame(minHeight: Metrics.minimumTouchTarget)
                                    .accessibilityHint("Keeps what you’ve answered and goes to the last step.")
                                    .accessibilityIdentifier("setup-skip-all")
                            }
                        }
                        .padding(.top, Metrics.md)
                        ForEach(transcript, id: \.self) { asked in
                            exchange(asked)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, Metrics.lg)
                    .frame(maxWidth: Metrics.contentMaxWidth)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .defaultScrollAnchor(.bottom)
                // Earlier answers fade out under the status bar instead of
                // colliding with it.
                .mask(
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: Metrics.xl)
                        Color.black
                    }
                )
                .safeAreaInset(edge: .bottom, spacing: Metrics.xs) {
                    controls
                        .padding(Metrics.md)
                        .auroraGlass(cornerRadius: Metrics.heroRadius)
                        .padding(.horizontal, Metrics.sm)
                        .padding(.bottom, Metrics.xs)
                        .frame(maxWidth: Metrics.contentMaxWidth)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controlsHeight = $0 }
                }
                // A new question, or controls that grew taller, would
                // otherwise leave the latest question behind them.
                .onChange(of: step) { _, newStep in
                    scrollToEnd(proxy)
                    UIAccessibility.post(notification: .announcement, argument: SetupCopy.question(newStep, modelAvailable: modelAvailable))
                }
                .onChange(of: controlsHeight) { _, _ in scrollToEnd(proxy) }
                .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            }
        }
        .background(Palette.screen.ignoresSafeArea())
        .sheet(isPresented: $showCalendars) {
            CalendarConnectionsView(service: assistant.calendars)
        }
        .onAppear { name = model.state.prefs.displayName ?? "" }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        Task { @MainActor in
            withAnimation(Motion.content(reduceMotion: reduceMotion)) { proxy.scrollTo("end", anchor: .bottom) }
        }
    }

    // MARK: Transcript

    /// Every question asked so far, the current one last.
    private var transcript: [SetupStep] {
        SetupStep.allCases.filter { $0.rawValue <= step.rawValue }
    }

    @ViewBuilder private func exchange(_ asked: SetupStep) -> some View {
        bubble(SetupCopy.question(asked, modelAvailable: modelAvailable), fromAurora: true)
            .accessibilityIdentifier("setup-question-\(asked)")
        if asked != step, let answer = answer(asked) {
            bubble(answer, fromAurora: false)
        }
    }

    private func bubble(_ text: String, fromAurora: Bool) -> some View {
        Text(text)
            .font(Typography.evidence)
            .foregroundStyle(Palette.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Metrics.md)
            .padding(.vertical, Metrics.sm)
            .background(
                fromAurora ? Palette.card : Palette.selectionFill,
                in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
            )
            .frame(maxWidth: .infinity, alignment: fromAurora ? .leading : .trailing)
            .accessibilityLabel("\(fromAurora ? "Aurora" : "You"): \(text)")
            .transition(Motion.stateTransition(reduceMotion: reduceMotion))
    }

    private func answer(_ step: SetupStep) -> String? {
        let state = model.state
        switch step {
        case .name: return state.prefs.displayName ?? "Skip for now"
        case .sleepTarget: return OnboardingCopy.formatSleepTarget(state.prefs.targetSleep).spoken
        case .health: return SetupCopy.healthAnswer(state.healthChoices, healthAvailable: model.healthAvailable)
        case .calendar: return assistant.calendars.selected.isEmpty ? "Not now" : "Calendars chosen"
        case .finish: return nil
        }
    }

    // MARK: Controls

    @ViewBuilder private var controls: some View {
        VStack(alignment: .leading, spacing: Metrics.sm) {
            switch step {
            case .name: nameControls
            case .sleepTarget: sleepTargetControls
            case .health: healthControls
            case .calendar: calendarControls
            case .finish: finishControls
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Motion.stateChange(reduceMotion: reduceMotion), value: step)
    }

    private var nameControls: some View {
        VStack(spacing: Metrics.sm) {
            TextField("First name", text: $name)
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .submitLabel(.continue)
                .focused($nameFocused)
                .onSubmit(saveName)
                .padding(.horizontal, Metrics.md)
                .frame(minHeight: Metrics.minimumTouchTarget)
                .background(Palette.fieldBackground, in: RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
                .accessibilityLabel("First name")
                .accessibilityIdentifier("setup-name")
            actionRow(primary: "Continue", primaryDisabled: Welcome.cleanName(name) == nil, primaryAction: saveName) {
                nameFocused = false
                model.setDisplayName(nil)
                advance()
            }
        }
    }

    private var sleepTargetControls: some View {
        let target = model.state.prefs.targetSleep
        let formatted = OnboardingCopy.formatSleepTarget(target)
        return VStack(alignment: .leading, spacing: Metrics.sm) {
            Stepper(
                value: Binding(get: { target }, set: { model.setSleepTarget($0) }),
                in: OnboardingCopy.sleepTargetRange,
                step: OnboardingCopy.sleepTargetStep
            ) {
                Text("\(formatted.value) \(formatted.unit)")
                    .font(Typography.value.monospacedDigit())
                    .foregroundStyle(Palette.textPrimary)
            }
            .accessibilityLabel("Sleep target")
            .accessibilityValue(formatted.spoken)
            Button("Continue") { advance() }
                .buttonStyle(.auroraPrimary)
                .accessibilityIdentifier("setup-next")
        }
    }

    private var healthControls: some View {
        let state = model.state
        let available = model.healthAvailable
        return VStack(alignment: .leading, spacing: Metrics.sm) {
            if available {
                ForEach(Self.healthChoices, id: \.self) { choice in
                    healthRow(choice, on: state.healthChoices[choice], disabled: working != nil || state.demoMode)
                }
            }
            Text(SetupCopy.healthNote(state.healthChoices, healthAvailable: available, permission: state.onboarding.permissionStatus, demoMode: state.demoMode))
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("setup-health-note")
            let anyOn = Self.healthChoices.contains { state.healthChoices[$0] }
            if anyOn {
                Button("Continue") { leaveHealth() }
                    .buttonStyle(.auroraPrimary)
                    .disabled(working != nil)
                    .accessibilityIdentifier("setup-next")
            } else {
                Button("Not now") { leaveHealth() }
                    .buttonStyle(.auroraSecondary)
                    .disabled(working != nil)
                    .accessibilityIdentifier("setup-skip")
            }
        }
    }

    private func healthRow(_ choice: HealthChoice, on: Bool, disabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: Metrics.xxs) {
            Toggle(isOn: Binding(get: { on }, set: { setHealth(choice, $0) })) {
                HStack(spacing: Metrics.xs) {
                    Text(choice.title).font(Typography.cardTitle).foregroundStyle(Palette.textPrimary)
                    if working == choice { ProgressView() }
                }
            }
            .disabled(disabled)
            .frame(minHeight: Metrics.minimumTouchTarget)
            .accessibilityHint(choice.detail)
            .accessibilityIdentifier("setup-health-\(choice.rawValue)")
            if let message = healthMessages[choice] {
                Text(message).font(.footnote).foregroundStyle(StatusTone.warning.foreground)
            }
        }
    }

    /// Opens the same connection sheet as Settings. Nothing connects or is
    /// selected unless the person does it there.
    @ViewBuilder private var calendarControls: some View {
        if assistant.calendars.selected.isEmpty {
            actionRow(primary: "Choose calendars", primaryDisabled: false, primaryAction: { showCalendars = true }) { advance() }
        } else {
            VStack(spacing: Metrics.xs) {
                Button("Continue") { advance() }
                    .buttonStyle(.auroraPrimary)
                    .accessibilityIdentifier("setup-next")
                Button("Change calendars") { showCalendars = true }
                    .buttonStyle(.auroraSecondary)
            }
        }
    }

    private var finishControls: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            Button("Start with Aurora") { model.completeOnboarding() }
                .buttonStyle(.auroraPrimary)
                .accessibilityIdentifier("setup-finish")
            Button("Explore with Sample Data") {
                model.loadSampleData()
                model.completeOnboarding()
            }
            .buttonStyle(.auroraSecondary)
            .accessibilityIdentifier("setup-sample")
            Text(SetupCopy.sampleNote)
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One primary action, then a quiet "Not now", stacked at every size.
    private func actionRow(primary: String, primaryDisabled: Bool, primaryAction: @escaping () -> Void, skip: @escaping () -> Void) -> some View {
        VStack(spacing: Metrics.xs) {
            Button(primary, action: primaryAction)
                .buttonStyle(.auroraPrimary)
                .disabled(primaryDisabled)
                .accessibilityIdentifier("setup-next")
            Button("Not now", action: skip)
                .buttonStyle(.auroraSecondary)
                .accessibilityIdentifier("setup-skip")
        }
    }

    // MARK: Actions

    private func saveName() {
        guard Welcome.cleanName(name) != nil else { return }
        model.setDisplayName(name)
        nameFocused = false
        advance()
    }

    /// The same path as Apple Health settings: each choice asks Health for
    /// its own permission, and the result is reported, never assumed.
    private func setHealth(_ choice: HealthChoice, _ enabled: Bool) {
        Task {
            working = choice
            healthMessages[choice] = nil
            let result = await model.setHealthChoice(choice, enabled: enabled)
            healthMessages[choice] = result.message
            working = nil
        }
    }

    /// Without Health sleep, sleep is logged by hand. A declined request
    /// already set that, with its own status, so it isn't overwritten.
    private func settleSleepSource() {
        let state = model.state
        if state.onboarding.source == .healthkit && !state.healthChoices.readSleep {
            model.chooseSleepSource(.manual)
        }
    }

    private func leaveHealth() {
        settleSleepSource()
        advance()
    }

    private func leave(to target: SetupStep) {
        nameFocused = false
        settleSleepSource()
        withAnimation(Motion.stateChange(reduceMotion: reduceMotion)) { model.setSetupStep(target) }
    }

    private func advance() {
        withAnimation(Motion.stateChange(reduceMotion: reduceMotion)) { model.setSetupStep(step.next) }
    }
}
