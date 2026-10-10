import AuroraCore
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// Settings: appearance, the values estimates use, the user's own reference
/// points, the cutoff reminder, About, and Data (exports and deletion). The
/// stored caffeine reference is never framed as a safe amount or a goal.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(PurchaseService.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var confirmDelete = false
    @State private var reminderBusy = false
    @State private var deletedCount = 0

    static let privacyPolicyURL = URL(string: "https://nmapaye.github.io/aurora/privacy.html")!
    static let supportURL = URL(string: "https://nmapaye.github.io/aurora/support.html")!

    var body: some View {
        let state = model.state
        let prefs = state.prefs
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        PlusView()
                    } label: {
                        row("Aurora Plus", detail: purchases.isUnlocked
                            ? "Unlocked. Thank you for supporting Aurora."
                            : "Two-week and month views. One purchase, no subscription.")
                    }
                    .accessibilityIdentifier("settings-plus")
                }

                Section("Appearance") {
                    Picker("Appearance", selection: Binding(get: { state.appearanceMode }, set: { model.setAppearance($0) })) {
                        Text("System").tag(AppearanceMode.system)
                        Text("Light").tag(AppearanceMode.light)
                        Text("Dark").tag(AppearanceMode.dark)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    stepper("Caffeine half-life", value: prefs.halfLife, in: 0.5...16, step: 0.5, text: hoursText) { v in
                        model.setPrefs { $0.halfLife = v }
                    }
                } footer: { Text("Used to estimate active caffeine.") }

                Section {
                    stepper("Daily sleep target", value: prefs.targetSleep, in: 5...10, step: 0.5, text: hoursText) { v in
                        model.setPrefs { $0.targetSleep = v }
                    }
                } footer: { Text("Your own sleep goal. Summary and Sleep compare against it, and the alertness estimate uses it.") }

                Section {
                    stepper("Personal caffeine reference", value: prefs.dailyLimitMg, in: 0...1000, step: 20, text: { "\(numberText($0)) mg" }) { v in
                        model.setPrefs { $0.dailyLimitMg = v }
                    }
                } footer: { Text("A daily amount you choose for your own reference. It is not a recommended or safe amount.") }

                Section {
                    stepper("Cutoff hour", value: jsRound(prefs.cutoffHour), in: 0...23, step: 1, text: { model.text.clockHour($0, clock: model.clock) }) { v in
                        model.setPrefs { $0.cutoffHour = v }
                        Task { await model.resyncReminder() }
                    }
                } header: {
                    Text("Estimates and References")
                } footer: { Text("The time you choose for the cutoff marker and optional reminder.") }

                Section("Notifications") {
                    Toggle(isOn: Binding(get: { prefs.notifyCutoff }, set: { enabled in
                        Task {
                            reminderBusy = true
                            await model.setReminder(enabled: enabled)
                            reminderBusy = false
                        }
                    })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cutoff reminder")
                            Text("Daily at \(model.text.clockHour(prefs.cutoffHour, clock: model.clock)), the cutoff time you chose.")
                                .font(.footnote)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    reminderStatusRow(enabled: prefs.notifyCutoff)
                }

                Section("About") {
                    Button { openURL(Self.privacyPolicyURL) } label: {
                        row("Privacy Policy", detail: "Read-only Health sleep access, local storage, exports, and deletion.")
                    }
                    Button { openURL(Self.supportURL) } label: {
                        row("Support", detail: "Get help, report issues, and avoid sharing private Health data.")
                    }
                    row("Medical disclaimer", detail: "Aurora is informational only and does not diagnose, treat, cure, or prevent any disease or condition.")
                    LabeledContent("Version", value: Self.version)
                }

                Section {
                    row("Stored on this device", detail: "Aurora keeps your entries on this iPhone or iPad. Deleting them does not change Apple Health.")
                    ShareLink(item: CSVFile(name: "aurora-caffeine-entries.csv") { [doses = state.doses, clock = model.clock] in
                        Export.doseEntriesCSV(doses, clock: clock)
                    },
                              preview: SharePreview("Caffeine entries")) {
                        row("Export Caffeine Entries", detail: "CSV of every recorded entry (\(state.doses.count)), with its source.")
                    }
                    ShareLink(item: CSVFile(name: "aurora-daily-caffeine.csv") { [doses = state.doses, now = model.now, clock = model.clock] in
                        Export.dailyTotalsCSV(Export.dailyTotalRows(doses, now: now, clock: clock))
                    },
                              preview: SharePreview("Daily caffeine totals")) {
                        row("Export Daily Caffeine Totals", detail: "CSV by day. Days without entries are marked “no record”, not 0 mg.")
                    }
                    ShareLink(item: CSVFile(name: "aurora-reaction-tests.csv") { [sessions = state.vigilanceSessions] in
                        Export.vigilanceSessionsCSV(sessions)
                    },
                              preview: SharePreview("Reaction Tests")) {
                        row("Export Reaction Tests", detail: "CSV of every Reaction Test (\(state.vigilanceSessions.count)), with its source.")
                    }
                    Button("Delete All Data", role: .destructive) { confirmDelete = true }
                        .accessibilityIdentifier("delete-all-data")
                    if let result = model.deletionResult {
                        Text(result == .completed
                             ? "All Aurora data was deleted from this device."
                             : "Some Aurora files couldn’t be removed. Try Delete All Data again.")
                            .font(.footnote)
                            .foregroundStyle(result == .completed ? Palette.textSecondary : StatusTone.error.foreground)
                            .accessibilityIdentifier("delete-all-result")
                    }
                } header: {
                    Text("Data")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.modalBackground)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Delete all Aurora data?", isPresented: $confirmDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    deletedCount += 1
                    model.deleteAllData()
                }
            } message: {
                Text("This removes every caffeine entry, sleep session, and reaction test stored in Aurora, along with copies of unreadable files, the previous version’s data, and exported CSV files. Your Apple Health data is not changed.")
            }
            .sensoryFeedback(.warning, trigger: deletedCount)
            .task { await model.resyncReminder() }
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    private func hoursText(_ value: Double) -> String {
        "\(OnboardingCopy.formatSleepTarget(value).value) h"
    }

    private func stepper(
        _ title: String,
        value: Double,
        in range: ClosedRange<Double>,
        step: Double,
        text: @escaping (Double) -> String,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        Stepper(value: Binding(get: { value }, set: onChange), in: range, step: step) {
            LabeledContent(title, value: text(value))
        }
        .accessibilityValue(text(value))
    }

    @ViewBuilder
    private func reminderStatusRow(enabled: Bool) -> some View {
        let status: (text: String, failed: Bool) = {
            if reminderBusy { return ("Updating reminder…", false) }
            switch model.reminderStatus {
            case .off: return (enabled ? "Updating reminder…" : "Reminder off.", false)
            case .scheduled: return ("Reminder scheduled.", false)
            case .denied: return ("Notification permission is off. Allow notifications in system Settings, then retry.", true)
            case .failed: return ("The reminder couldn’t be scheduled. Retry.", true)
            }
        }()
        VStack(alignment: .leading, spacing: 2) {
            Text("Reminder status")
            Text(status.text)
                .font(.footnote)
                .foregroundStyle(status.failed ? StatusTone.error.foreground : Palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(status.failed ? .isStaticText : [])
        if status.failed {
            Button("Retry reminder") {
                Task { await model.setReminder(enabled: true) }
            }
        }
    }

    private func row(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(Palette.textPrimary)
            Text(detail).font(.footnote).foregroundStyle(Palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A CSV export handed to the share sheet as a file. The text is built only
/// when the share actually happens, not each time Settings draws, and
/// exports are written to one temporary folder so Delete All Data can remove
/// them.
struct CSVFile: Transferable {
    let name: String
    let contents: @Sendable () -> String

    init(name: String, contents: @escaping @Sendable () -> String) {
        self.name = name
        self.contents = contents
    }

    init(name: String, text: String) {
        self.init(name: name) { text }
    }

    static var exportDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("AuroraExports", isDirectory: true)
    }

    static func purgeExports() throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: exportDirectory.path) {
            try manager.removeItem(at: exportDirectory)
        }
    }

    /// Writes the file into `directory`, the shared export folder unless a
    /// test passes its own.
    func write(to directory: URL = CSVFile.exportDirectory) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data(contents().utf8).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            SentTransferredFile(try file.write())
        }
    }
}
