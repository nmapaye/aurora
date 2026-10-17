import AuroraCore
import SwiftUI

/// Apple Health choices. Each permission is its own opt-in, and nothing asks
/// Health for anything until the person turns that choice on.
struct HealthConnectionView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var working: HealthChoice?
    @State private var messages: [HealthChoice: String] = [:]
    @State private var refreshing = false
    @State private var retrying = false

    var body: some View {
        let state = app.state
        let status = SleepDataStatus.describe(
            onboarding: state.onboarding, healthSync: state.healthSync,
            demoMode: state.demoMode, healthAvailable: app.healthAvailable
        )
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.lg) {
                    // The bar already says Apple Health; no second heading.
                    Text("Choose each permission separately.")
                        .accessibilityIdentifier("assistant-health-disclosure")
                    choices(state.healthChoices)
                    Card {
                        SectionLabel(text: "Status")
                        Text(status.state).font(Typography.cardTitle)
                        Text(status.detail).font(.footnote).foregroundStyle(Palette.textSecondary)
                        if let message = state.healthSync.lastMessage {
                            Text(message).font(.footnote).foregroundStyle(Palette.textSecondary)
                        }
                        if let read = state.healthLedger.caffeineReadSummary {
                            Text(read).font(.footnote).foregroundStyle(Palette.textSecondary)
                        }
                        // Offered only when a stored read position couldn't be
                        // decoded. Records stay; reading starts over by UUID.
                        ForEach(state.healthLedger.kindsNeedingRestart, id: \.self) { kind in
                            Button(kind == .caffeine ? "Restart reading caffeine" : "Restart reading sleep") {
                                Task { await app.restartHealthReading(kind) }
                            }
                            .buttonStyle(.auroraSecondary)
                            .accessibilityIdentifier("assistant-health-restart-\(kind.rawValue)")
                        }
                        Button {
                            Task {
                                refreshing = true
                                await app.refresh(.explicit)
                                refreshing = false
                            }
                        } label: {
                            HStack {
                                if refreshing { ProgressView() }
                                Text(refreshing ? "Refreshing…" : "Refresh from Health")
                            }
                        }
                        .buttonStyle(.auroraSecondary)
                        .disabled(refreshing || state.healthChoices.observedKinds.isEmpty || !app.healthAvailable)
                        .accessibilityIdentifier("assistant-health-connect")
                    }
                    if let outbox = state.healthLedger.outboxSummary {
                        Card {
                            SectionLabel(text: "Aurora’s entries in Health")
                            StatusBadge(text: "Not all changes are in Apple Health", tone: .warning)
                            Text(outbox).font(.footnote).foregroundStyle(Palette.textSecondary)
                            Button {
                                Task {
                                    retrying = true
                                    await app.retryHealthExports()
                                    retrying = false
                                }
                            } label: {
                                HStack {
                                    if retrying { ProgressView() }
                                    Text(retrying ? "Retrying…" : "Retry Apple Health")
                                }
                            }
                            .buttonStyle(.auroraPrimary)
                            .disabled(retrying || !state.healthExportActive)
                            .accessibilityIdentifier("assistant-health-retry")
                        }
                    }
                    Text("Delete All Records and Erase all local data leave Aurora’s earlier entries in Apple Health. Delete them in the Health app.")
                        .font(.footnote).foregroundStyle(Palette.textSecondary)
                }
                .padding(Metrics.lg).frame(maxWidth: Metrics.contentMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.screen)
            .navigationTitle("Apple Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("assistant-health-done")
                }
            }
        }
    }

    /// The choices, then "Read-only in Aurora" once as their footer.
    private func choices(_ chosen: HealthChoices) -> some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            Card {
                ForEach(Array(HealthChoice.allCases.enumerated()), id: \.element) { index, choice in
                    if index > 0 { Divider().overlay(Palette.separator) }
                    choiceRow(choice, on: chosen[choice])
                }
            }
            Text("Read-only in Aurora: sleep and caffeine imported from Health.")
                .font(.footnote).foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, Metrics.xxs)
        }
    }

    private func choiceRow(_ choice: HealthChoice, on: Bool) -> some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            choiceToggle(choice, on: on)
            if on { Text(choice.requestedNote).font(.footnote).foregroundStyle(Palette.textSecondary) }
            if let message = messages[choice] {
                Text(message).font(.footnote).foregroundStyle(StatusTone.warning.foreground)
            }
        }
    }

    /// The label holds the title and description, so at accessibility sizes
    /// they wrap together beside the switch. VoiceOver hears the title as
    /// the switch's label and the description as its hint.
    private func choiceToggle(_ choice: HealthChoice, on: Bool) -> some View {
        Toggle(isOn: Binding(get: { on }, set: { set(choice, $0) })) {
            VStack(alignment: .leading, spacing: Metrics.xxs) {
                HStack(spacing: Metrics.xs) {
                    Text(choice.title).font(Typography.cardTitle)
                    if working == choice { ProgressView() }
                }
                Text(choice.detail).font(.footnote).foregroundStyle(Palette.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        // Background updates apply only to kinds Aurora already reads.
        .disabled(disabled(choice, on: on))
        .frame(minHeight: Metrics.minimumTouchTarget)
        .accessibilityLabel(choice.title)
        .accessibilityHint(choice.detail)
        .accessibilityIdentifier("assistant-health-\(choice.rawValue)")
    }

    private func disabled(_ choice: HealthChoice, on: Bool) -> Bool {
        working != nil || !app.healthAvailable
            || (choice == .backgroundUpdates && !on && app.state.healthChoices.observedKinds.isEmpty)
    }

    private func set(_ choice: HealthChoice, _ enabled: Bool) {
        Task {
            working = choice
            messages[choice] = nil
            let result = await app.setHealthChoice(choice, enabled: enabled)
            messages[choice] = result.message
            working = nil
        }
    }
}
