import AuroraCore
import SwiftUI

/// Connection review only. The user must tap before any Health permission request.
struct HealthConnectionView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var connecting = false

    var body: some View {
        let status = SleepDataStatus.describe(
            onboarding: app.state.onboarding, healthSync: app.state.healthSync,
            demoMode: app.state.demoMode, healthAvailable: app.healthAvailable
        )
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("Sleep from Apple Health", systemImage: "heart.text.square")
                        .font(.title2.weight(.semibold))
                    Text("Aurora requests read-only access to sleep records. It never writes to Apple Health or reads other health metrics.")
                        .accessibilityIdentifier("assistant-health-disclosure")
                    Text(status.state).font(.headline)
                    Text(status.detail).foregroundStyle(Palette.textSecondary)
                    if let message = app.state.healthSync.lastMessage {
                        Text(message).font(.footnote).foregroundStyle(Palette.textSecondary)
                    }
                    Button {
                        Task {
                            connecting = true
                            await app.connectHealth()
                            connecting = false
                        }
                    } label: {
                        HStack {
                            if connecting { ProgressView() }
                            Text(connecting ? "Connecting…" : app.state.onboarding.permissionStatus == .granted ? "Refresh Sleep" : "Connect to Health")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.auroraPrimary)
                    .disabled(connecting || !app.healthAvailable)
                    .accessibilityIdentifier("assistant-health-connect")
                }
                .padding(20).frame(maxWidth: Metrics.contentMaxWidth)
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
}
