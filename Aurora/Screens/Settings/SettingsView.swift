import AuroraCore
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// Settings: appearance, the values estimates use, the user's own reference
/// points, the cutoff reminder, About, and Data (exports and deletion). The
/// stored caffeine reference is never framed as a safe amount or a goal.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AssistantModel.self) private var assistant
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var confirmDelete = false
    @State private var confirmErase = false
    @State private var reminderBusy = false
    @State private var deletedCount = 0

    static let privacyPolicyURL = URL(string: "https://nmapaye.github.io/aurora/privacy.html")!
    static let supportURL = URL(string: "https://nmapaye.github.io/aurora/support.html")!

    /// True when pushed onto another screen's NavigationStack. A second
    /// stack nested inside it crashed iPadOS 26's focus system as soon as
    /// an alert appeared.
    var pushed = false

    var body: some View {
        if pushed {
            settings
        } else {
            NavigationStack { settings }
        }
    }

    // A plain scrolling stack, not a Form: on iPadOS 26.5 with a keyboard
    // attached, any alert presented over a scrolled Form crashed UIKit's
    // focus system on the Form's lazily built rows.
    private var settings: some View {
        let state = model.state
        let prefs = state.prefs
        return ScrollView {
            VStack(alignment: .leading, spacing: Metrics.lg) {
                group("Appearance") {
                    Picker("Appearance", selection: Binding(get: { state.appearanceMode }, set: { model.setAppearance($0) })) {
                        Text("System").tag(AppearanceMode.system)
                        Text("Light").tag(AppearanceMode.light)
                        Text("Dark").tag(AppearanceMode.dark)
                    }
                    .pickerStyle(.segmented)
                }

                group("Estimates and References") {
                    stepper("Caffeine half-life", value: prefs.halfLife, in: 0.5...16, step: 0.5, text: hoursText) { v in
                        model.setPrefs { $0.halfLife = v }
                    }
                    footnote("Used to estimate active caffeine.")
                    Divider()
                    stepper("Daily sleep target", value: prefs.targetSleep, in: 5...10, step: 0.5, text: hoursText) { v in
                        model.setPrefs { $0.targetSleep = v }
                    }
                    footnote("Your own sleep goal. Summary and Sleep compare against it, and the alertness estimate uses it.")
                    Divider()
                    stepper("Personal caffeine reference", value: prefs.dailyLimitMg, in: 0...1000, step: 20, text: { "\(numberText($0)) mg" }) { v in
                        model.setPrefs { $0.dailyLimitMg = v }
                    }
                    footnote("A daily amount you choose for your own reference. It is not a recommended or safe amount.")
                    Divider()
                    stepper("Cutoff hour", value: jsRound(prefs.cutoffHour), in: 0...23, step: 1, text: { model.text.clockHour($0, clock: model.clock) }) { v in
                        model.setPrefs { $0.cutoffHour = v }
                        Task { await model.resyncReminder() }
                    }
                    footnote("The time you choose for the cutoff marker and optional reminder.")
                }

                group("Notifications") {
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
                    Divider()
                    reminderStatusRow(enabled: prefs.notifyCutoff)
                }

                group("About") {
                    linkRow("Privacy Policy", detail: "Separate Health sleep and caffeine reads, optional caffeine writes, local storage, exports, and deletion.") { openURL(Self.privacyPolicyURL) }
                    Divider()
                    linkRow("Support", detail: "Get help, report issues, and avoid sharing private Health data.") { openURL(Self.supportURL) }
                    Divider()
                    row("Medical disclaimer", detail: "Aurora is informational only and does not diagnose, treat, cure, or prevent any disease or condition.")
                    Divider()
                    LabeledContent("Version", value: Self.version)
                }

                group("Data") {
                    row("Stored on this device", detail: "Aurora keeps your entries on this iPhone or iPad. Deleting them does not change Apple Health.")
                    Divider()
                    ShareLink(item: CSVFile(name: "aurora-caffeine-entries.csv") { [doses = state.doses, clock = model.clock] in
                        Export.doseEntriesCSV(doses, clock: clock)
                    },
                              preview: SharePreview("Caffeine entries")) {
                        row("Export Caffeine Entries", detail: "CSV of every recorded entry (\(state.doses.count)), with its source.", tinted: true)
                    }
                    Divider()
                    ShareLink(item: CSVFile(name: "aurora-daily-caffeine.csv") { [doses = state.doses, now = model.now, clock = model.clock] in
                        Export.dailyTotalsCSV(Export.dailyTotalRows(doses, now: now, clock: clock))
                    },
                              preview: SharePreview("Daily caffeine totals")) {
                        row("Export Daily Caffeine Totals", detail: "CSV by day. Days without entries are marked “no record”, not 0 mg.", tinted: true)
                    }
                    Divider()
                    ShareLink(item: CSVFile(name: "aurora-reaction-tests.csv") { [sessions = state.vigilanceSessions] in
                        Export.vigilanceSessionsCSV(sessions)
                    },
                              preview: SharePreview("Reaction Tests")) {
                        row("Export Reaction Tests", detail: "CSV of every Reaction Test (\(state.vigilanceSessions.count)), with its source.", tinted: true)
                    }
                    Divider()
                    destructiveButton("Delete recorded data", id: "delete-all-data") { confirmDelete = true }
                        .alert("Delete recorded data?", isPresented: $confirmDelete) {
                            Button("Cancel", role: .cancel) {}
                            Button("Delete", role: .destructive) {
                                deletedCount += 1
                                model.deleteAllData()
                            }
                        } message: {
                            Text("This clears current caffeine, sleep, and reaction records. Settings, conversation snapshots, and recovery copies remain. Apple Health data is not changed.")
                        }
                    footnote("Record-only deletion keeps settings and conversation snapshots. Use Erase all local data to remove retained copies too.")
                    destructiveButton("Erase all local data", id: "erase-all-local-data") { confirmErase = true }
                        .alert("Erase all local Aurora data?", isPresented: $confirmErase) {
                            Button("Erase all local data", role: .destructive) {
                                assistant.requestErase()
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This permanently removes records, conversation, recovery and migration copies, preferences, local calendar connections, and Aurora reminders. Apple Health and external calendar events are not deleted. Export anything you want to keep first.")
                        }
                    if let failure = model.mutationFailure { Text(failure).foregroundStyle(Palette.destructive) }
                }
            }
            .frame(maxWidth: Metrics.contentMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(Metrics.md)
        }
        .background(Palette.modalBackground)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !pushed {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sensoryFeedback(.warning, trigger: deletedCount)
        .task { await model.resyncReminder() }
    }

    private func group<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        let rows = content()
        return VStack(alignment: .leading, spacing: Metrics.xs) {
            SectionLabel(text: label).padding(.horizontal, Metrics.xxs)
            Card { rows }
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func linkRow(_ title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline) {
                row(title, detail: detail, tinted: true)
                Spacer(minLength: Metrics.xs)
                Image(systemName: "arrow.up.right").font(.footnote).foregroundStyle(Palette.textSecondary).accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isLink)
    }

    private func destructiveButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Text(title).foregroundStyle(Palette.destructive)
                .frame(maxWidth: .infinity, minHeight: Metrics.minimumTouchTarget, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    private func hoursText(_ value: Double) -> String {
        "\(OnboardingCopy.formatSleepTarget(value).value)h"
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

    private func row(_ title: String, detail: String, tinted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(tinted ? Palette.tint : Palette.textPrimary)
            Text(detail).font(.footnote).foregroundStyle(Palette.textSecondary)
        }
        // Share link labels center wrapped text by default.
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
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
