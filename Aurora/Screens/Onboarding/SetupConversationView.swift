import AuroraCore
import SwiftUI

/// First-run setup as a short conversation. Aurora asks one question at a
/// time; every question has its own "Not now", and "Skip to the end" leaves
/// setup at any point. An answer, its outcome and the next step are saved
/// together, so a relaunch resumes at the next question; if that save
/// fails, the question stays with the error and can be retried. The
/// transcript shows only questions actually asked and what the person did.
/// Health and calendars use the same connection services as Settings, and
/// nothing is requested until the person chooses it here. Health access is
/// never shown as granted.
struct SetupConversationView: View {
    @Environment(AppModel.self) private var model
    @Environment(AssistantModel.self) private var assistant
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var controlsHeight: CGFloat = 0
    @State private var name = ""
    /// Edited here and saved only by Continue, so "Not now" keeps the stored target.
    @State private var targetDraft: Double?
    /// The last failed save, shown above the controls until the next try.
    @State private var saveFailure: String?
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
                                Button("Skip to the end", action: skipToEnd)
                                    .font(.subheadline.weight(.medium))
                                    .frame(minHeight: Metrics.minimumTouchTarget)
                                    .accessibilityHint("Keeps what you’ve answered and goes to the last step.")
                                    .accessibilityIdentifier("setup-skip-all")
                            }
                        }
                        .padding(.top, Metrics.md)
                        ForEach(transcript, id: \.step) { entry in
                            exchange(entry)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, Metrics.lg)
                    .frame(maxWidth: Metrics.contentMaxWidth)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .defaultScrollAnchor(.bottom)
                // Keeps scrolled-to content, such as a question's first line,
                // below the fade rather than inside it.
                .safeAreaPadding(.top, Metrics.xl)
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
                .onAppear { proxy.scrollTo(latestQuestion, anchor: .top) }
            }
        }
        .background(Palette.screen.ignoresSafeArea())
        .sheet(isPresented: $showCalendars) {
            CalendarConnectionsView(service: assistant.calendars)
        }
        .onAppear { name = model.state.prefs.displayName ?? "" }
    }

    /// Shows the current question from its first line. When it fits above
    /// the controls the scroll stops at the end, as before; when it's taller
    /// (largest text), its start stays visible instead of being cut off.
    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        let target = latestQuestion
        Task { @MainActor in
            withAnimation(Motion.content(reduceMotion: reduceMotion)) { proxy.scrollTo(target, anchor: .top) }
        }
    }

    private var latestQuestion: String {
        transcript.last.map { Self.questionAnchor($0.step) } ?? "end"
    }

    private static func questionAnchor(_ step: SetupStep) -> String { "question-\(step.rawValue)" }

    // MARK: Transcript

    /// Questions actually asked, with what the person really did, then the
    /// current question. Nothing is inferred from progress alone.
    private var transcript: [SetupTranscript.Entry] {
        SetupTranscript.entries(
            state: model.state,
            healthAvailable: model.healthAvailable,
            calendarsChosen: !assistant.calendars.selected.isEmpty,
            modelAvailable: modelAvailable
        )
    }

    @ViewBuilder private func exchange(_ entry: SetupTranscript.Entry) -> some View {
        bubble(entry.question, speaker: "Aurora", fill: Palette.card, alignment: .leading)
            .id(Self.questionAnchor(entry.step))
            .accessibilityIdentifier("setup-question-\(entry.step)")
        switch entry.reply {
        case .person(let text)?:
            bubble(text, speaker: "You", fill: Palette.selectionFill, alignment: .trailing)
        case .retained(let text)?:
            // A setting that stayed as it was: Aurora's note, not a reply.
            bubble(text, speaker: "Aurora", fill: Palette.cardMuted, alignment: .leading)
                .accessibilityIdentifier("setup-retained-\(entry.step)")
        case nil:
            EmptyView()
        }
    }

    private func bubble(_ text: String, speaker: String, fill: Color, alignment: Alignment) -> some View {
        Text(text)
            .font(Typography.evidence)
            .foregroundStyle(Palette.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Metrics.md)
            .padding(.vertical, Metrics.sm)
            .background(fill, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .frame(maxWidth: .infinity, alignment: alignment)
            .accessibilityLabel("\(speaker): \(text)")
            .transition(Motion.stateTransition(reduceMotion: reduceMotion))
    }

    // MARK: Controls

    @ViewBuilder private var controls: some View {
        VStack(alignment: .leading, spacing: Metrics.sm) {
            if let saveFailure {
                Label(saveFailure, systemImage: StatusTone.error.symbol)
                    .font(.footnote)
                    .foregroundStyle(StatusTone.error.foreground)
                    .padding(.horizontal, Metrics.sm)
                    .padding(.vertical, Metrics.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(StatusTone.error.background, in: RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("setup-save-failure")
            }
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
                record(.name, .skipped)
            }
        }
    }

    private var sleepTargetControls: some View {
        let target = targetDraft ?? model.state.prefs.targetSleep
        let formatted = OnboardingCopy.formatSleepTarget(target)
        return VStack(alignment: .leading, spacing: Metrics.sm) {
            Stepper(
                value: Binding(get: { target }, set: { targetDraft = $0 }),
                in: OnboardingCopy.sleepTargetRange,
                step: OnboardingCopy.sleepTargetStep
            ) {
                Text("\(formatted.value) \(formatted.unit)")
                    .font(Typography.value.monospacedDigit())
                    .foregroundStyle(Palette.textPrimary)
            }
            .accessibilityLabel("Sleep target")
            .accessibilityValue(formatted.spoken)
            .accessibilityIdentifier("setup-sleep-target")
            // Continue confirms the shown target; Not now keeps the stored one.
            actionRow(primary: "Continue", primaryDisabled: false, primaryAction: {
                record(.sleepTarget, .answered) { $0.prefs.targetSleep = target }
            }) {
                record(.sleepTarget, .skipped)
            }
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
                Button("Continue") { record(.health, .answered) { $0.settleSetupSleepSource() } }
                    .buttonStyle(.auroraPrimary)
                    .disabled(working != nil)
                    .accessibilityIdentifier("setup-next")
            } else {
                Button("Not now") { record(.health, .skipped) { $0.settleSetupSleepSource() } }
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
            actionRow(primary: "Choose calendars", primaryDisabled: false, primaryAction: { showCalendars = true }) {
                record(.calendar, .skipped)
            }
        } else {
            VStack(spacing: Metrics.xs) {
                Button("Continue") { record(.calendar, .answered) }
                    .buttonStyle(.auroraPrimary)
                    .accessibilityIdentifier("setup-next")
                Button("Change calendars") { showCalendars = true }
                    .buttonStyle(.auroraSecondary)
            }
        }
    }

    private var finishControls: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            Button("Start with Aurora") { finish(withSampleData: false) }
                .buttonStyle(.auroraPrimary)
                .accessibilityIdentifier("setup-finish")
            Button("Explore with Sample Data") { finish(withSampleData: true) }
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
        guard let cleaned = Welcome.cleanName(name) else { return }
        nameFocused = false
        record(.name, .answered) { $0.prefs.displayName = cleaned }
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

    /// Saves the answer, outcome and next step together. On failure the
    /// question stays, with the model's own error, so it can be retried.
    private func record(_ asked: SetupStep, _ outcome: SetupOutcome, answer: (inout AppState) -> Void = { _ in }) {
        var saved = false
        withAnimation(Motion.stateChange(reduceMotion: reduceMotion)) {
            saved = model.recordSetup(asked, outcome, answer: answer)
        }
        settle(saved)
        if saved { targetDraft = nil }
    }

    /// Questions not reached get no outcome, so none is shown as answered.
    private func skipToEnd() {
        nameFocused = false
        var saved = false
        withAnimation(Motion.stateChange(reduceMotion: reduceMotion)) { saved = model.skipSetupToEnd() }
        settle(saved)
    }

    /// Finishing is shown as done only once it was saved.
    private func finish(withSampleData: Bool) {
        settle(model.finishSetup(withSampleData: withSampleData))
    }

    private func settle(_ saved: Bool) {
        if saved {
            saveFailure = nil
            return
        }
        let message = model.mutationFailure ?? "Couldn't save this answer. Try again."
        saveFailure = message
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}
