import AuroraCore
import SwiftUI

/// First-run setup in three steps: a nightly sleep target, where sleep comes
/// from, and read-only Health access. Health access is never shown as
/// granted, because HealthKit doesn't reveal read decisions.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var step = 0
    @State private var requesting = false

    var body: some View {
        let onboarding = model.state.onboarding
        let copy = OnboardingCopy.stepCopy(step: step, source: onboarding.source)
        let isLast = step == OnboardingCopy.stepCount - 1
        let canAdvance = !isLast || onboarding.source == .manual || onboarding.permissionStatus != .idle

        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.xl) {
                    HStack(spacing: Metrics.sm) {
                        AuroraMark().frame(width: 40, height: 40)
                        Text("Step \(step + 1) of \(OnboardingCopy.stepCount)")
                            .font(.eyebrow)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    VStack(alignment: .leading, spacing: Metrics.xs) {
                        SectionLabel(text: copy.eyebrow)
                        Text(copy.title)
                            .font(.title.bold())
                            .foregroundStyle(Palette.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text(copy.body)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Group {
                        switch step {
                        case 0: sleepTarget
                        case 1: sources(onboarding.source)
                        default: permissions(onboarding)
                        }
                    }
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
                    .id(step)
                }
                .padding(Metrics.lg)
                .frame(maxWidth: Metrics.contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            actionBar(isLast: isLast, canAdvance: canAdvance)
        }
        .background(Palette.screen.ignoresSafeArea())
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.24), value: step)
        .onChange(of: step) { _, newStep in
            let title = OnboardingCopy.stepCopy(step: newStep, source: model.state.onboarding.source).title
            UIAccessibility.post(notification: .announcement, argument: "Step \(newStep + 1) of \(OnboardingCopy.stepCount). \(title)")
        }
    }

    private var sleepTarget: some View {
        let target = model.state.prefs.targetSleep
        let formatted = OnboardingCopy.formatSleepTarget(target)
        return VStack(alignment: .leading, spacing: Metrics.md) {
            Card {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
                    Text(formatted.value).font(.system(size: 48, weight: .bold).monospacedDigit())
                    Text(formatted.unit).font(.title3).foregroundStyle(Palette.textSecondary)
                }
                .foregroundStyle(Palette.textPrimary)
                .accessibilityHidden(true)
                Stepper(
                    "Sleep target",
                    value: Binding(get: { target }, set: { model.setSleepTarget($0) }),
                    in: OnboardingCopy.sleepTargetRange,
                    step: OnboardingCopy.sleepTargetStep
                )
                .accessibilityValue(formatted.spoken)
            }
            HStack(spacing: Metrics.sm) {
                ForEach(OnboardingCopy.sleepTargetPresets, id: \.self) { preset in
                    let selected = preset == target
                    Button("\(numberText(preset)) h") { model.setSleepTarget(preset) }
                        .buttonStyle(selected ? AnyButtonStyle(.auroraPrimary) : AnyButtonStyle(.auroraSecondary))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private func sources(_ selected: OnboardingSource) -> some View {
        VStack(spacing: Metrics.sm) {
            sourceOption(.healthkit, symbol: "heart", body: "Read recent sleep from the Health app. Aurora never writes to Health.", selected: selected)
            sourceOption(.manual, symbol: "square.and.pencil", body: "Log nights yourself. You can connect Health later from Sleep.", selected: selected)
        }
    }

    private func sourceOption(_ source: OnboardingSource, symbol: String, body: String, selected: OnboardingSource) -> some View {
        let isSelected = source == selected
        return Button {
            model.chooseSleepSource(source)
        } label: {
            HStack(alignment: .top, spacing: Metrics.sm) {
                Image(systemName: symbol).foregroundStyle(Palette.tint).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(OnboardingCopy.describeSleepSource(source)).font(.headline).foregroundStyle(Palette.textPrimary)
                    Text(body).font(.subheadline).foregroundStyle(Palette.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Palette.tint : Palette.textTertiary)
            }
            .padding(Metrics.md)
            .background(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).fill(isSelected ? Palette.selectionFill : Palette.card))
            .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(isSelected ? Palette.tint : Palette.cardBorder))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("source-\(source.rawValue)")
    }

    @ViewBuilder
    private func permissions(_ onboarding: Onboarding) -> some View {
        let sync = model.state.healthSync
        VStack(alignment: .leading, spacing: Metrics.md) {
            if onboarding.source == .manual {
                fact("Log as you go", "Add caffeine from Log and nights from Sleep. Aurora reads nothing from Health.")
            } else {
                fact("Sleep only", "Aurora requests read access to sleep analysis and nothing else.")
                fact("Read-only", "Aurora reads sleep only. It does not write anything back into the Health app.")
                fact("Your choice", "Pick what to share in the Health sheet, and change it anytime in the Health app.")
                StatusText(
                    text: "Status: \(OnboardingCopy.describeHealthAccess(source: onboarding.source, permission: onboarding.permissionStatus))",
                    tone: onboarding.permissionStatus == .granted ? .info : .neutral
                )
                if sync.importStatus == .failed {
                    Text("Health access requested, but the import failed. \(sync.lastMessage ?? "")")
                        .font(.footnote)
                        .foregroundStyle(StatusTone.error.foreground)
                }
                Button {
                    Task {
                        requesting = true
                        await model.requestHealthForOnboarding()
                        requesting = false
                    }
                } label: {
                    if requesting || sync.importStatus == .importing {
                        HStack { ProgressView(); Text("Importing recent sleep from Health…") }
                    } else {
                        Text("Allow Health Access")
                    }
                }
                .buttonStyle(.auroraPrimary)
                .disabled(requesting || onboarding.permissionStatus == .granted)
            }
            Text(OnboardingCopy.nextAction(
                source: onboarding.source, permission: onboarding.permissionStatus,
                importStatus: sync.importStatus, importedCount: sync.importedCount
            ))
            .font(.footnote)
            .foregroundStyle(Palette.textSecondary)
            Card {
                Text("Prefer to look around first?").font(.headline).foregroundStyle(Palette.textPrimary)
                Text("Finish setup with example nights and doses, labeled Sample Data throughout. Clear them anytime from Sleep.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                Button("Load Sample Data") { model.loadSampleData() }
                    .buttonStyle(.auroraSecondary)
                    .disabled(requesting)
            }
        }
    }

    private func fact(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline).foregroundStyle(Palette.textPrimary)
            Text(body).font(.subheadline).foregroundStyle(Palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func actionBar(isLast: Bool, canAdvance: Bool) -> some View {
        HStack(spacing: Metrics.sm) {
            if step > 0 {
                Button("Back") { step -= 1 }
                    .buttonStyle(.auroraSecondary)
                    .frame(maxWidth: 140)
            }
            Button(isLast ? "Finish setup" : "Continue") {
                if isLast {
                    model.completeOnboarding()
                } else {
                    step += 1
                }
            }
            .buttonStyle(.auroraPrimary)
            .disabled(!canAdvance || requesting)
            .accessibilityIdentifier("onboarding-continue")
        }
        .padding(Metrics.md)
        .frame(maxWidth: Metrics.contentMaxWidth)
        .frame(maxWidth: .infinity)
        .background(Palette.screen)
        .overlay(alignment: .top) { Divider().overlay(Palette.separator) }
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
