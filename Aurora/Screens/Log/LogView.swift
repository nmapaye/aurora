import AuroraCore
import SwiftUI

/// Log: what was recorded today and where it came from, Quick Add with Undo,
/// Custom Entry, and the five most recent entries with corrections. Nothing
/// here frames the total against a limit or a remaining amount.
struct LogView: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    @State private var confirmation: Confirmation?
    @State private var sheet: DoseSheet?
    @State private var customDraft: CustomDoseDraft?
    @State private var addedCount = 0

    struct Confirmation: Equatable {
        let dose: Dose
        let text: String
    }

    var body: some View {
        let state = model.state
        AppScreen(title: "Log") {
            WideColumns {
                loggedToday(state)
                quickAdd
            } trailing: {
                recent(state)
            }
        }
        .sensoryFeedback(.success, trigger: addedCount)
        .sheet(item: $sheet) { sheet in
            DoseEntrySheet(mode: sheet, draft: draft(for: sheet)) { result in
                handle(result, for: sheet)
            }
        }
    }

    private func loggedToday(_ state: AppState) -> some View {
        let summary = CaffeineLog.loggedToday(state.doses, now: model.now, clock: model.clock, formatTime: model.text.clockTime)
        return Card {
            Text(summary.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
            Text(summary.value)
                .font(.largeTitle.bold().monospacedDigit())
                .foregroundStyle(summary.sample ? Palette.textSecondary : Palette.textPrimary)
            if let source = summary.source {
                Text(source)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(summary.sample ? StatusTone.warning.foreground : Palette.textSecondary)
            }
            Text(summary.detail)
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.accessibilityLabel)
        .accessibilityIdentifier("logged-today")
    }

    private var quickAdd: some View {
        VStack(alignment: .leading, spacing: Metrics.sm) {
            SectionLabel(text: "Quick Add")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: Metrics.sm)], spacing: Metrics.sm) {
                ForEach(CaffeinePreset.all) { preset in
                    Button {
                        quickAdd(preset)
                    } label: {
                        VStack(alignment: .leading, spacing: Metrics.xxs) {
                            Image(systemName: preset.symbol).foregroundStyle(Palette.caffeineAccent)
                            Text(preset.label).font(.headline).foregroundStyle(Palette.textPrimary)
                            Text("\(numberText(preset.mg)) mg").font(.subheadline).foregroundStyle(Palette.textSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                        .padding(Metrics.sm)
                        .background(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).fill(Palette.card))
                        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(Palette.cardBorder))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Log \(preset.label), \(numberText(preset.mg)) mg")
                    .accessibilityIdentifier("quick-add-\(preset.id)")
                }
            }
            if let confirmation {
                HStack(spacing: Metrics.sm) {
                    Text(confirmation.text)
                        .font(.footnote)
                        .foregroundStyle(StatusTone.success.foreground)
                    Spacer(minLength: 0)
                    Button("Undo") { undo(confirmation) }
                        .font(.footnote.weight(.semibold))
                        .accessibilityIdentifier("quick-add-undo")
                }
                .padding(Metrics.sm)
                .background(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).fill(StatusTone.success.background))
                .transition(.opacity)
                .accessibilityIdentifier("quick-add-confirmation")
            }
            Button {
                sheet = .new
            } label: {
                Label("Custom Entry", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.auroraSecondary)
            .accessibilityIdentifier("custom-entry")
        }
    }

    private func recent(_ state: AppState) -> some View {
        VStack(alignment: .leading, spacing: Metrics.sm) {
            SectionLabel(text: "Recent")
            let doses = CaffeineLog.recent(state.doses)
            if doses.isEmpty {
                Text("No caffeine logged yet.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
            } else {
                Card(padding: 0) {
                    ForEach(Array(doses.enumerated()), id: \.element.id) { index, dose in
                        if index > 0 { Divider().overlay(Palette.separator).padding(.leading, Metrics.md) }
                        DoseRow(dose: dose) { sheet = .edit(dose) }
                    }
                }
            }
            Button("Show All Caffeine Data") { router.logPath.append(.caffeine) }
                .font(.subheadline.weight(.semibold))
                .padding(.top, Metrics.xxs)
        }
    }

    private func quickAdd(_ preset: CaffeinePreset) {
        guard let dose = model.quickAdd(preset) else { return }
        let text = CaffeineLog.quickAddConfirmation(dose, formatTime: model.text.clockTime)
        withAnimation { confirmation = Confirmation(dose: dose, text: text) }
        addedCount += 1
        UIAccessibility.post(notification: .announcement, argument: "\(text) Undo is available.")
    }

    private func undo(_ confirmation: Confirmation) {
        model.undo(confirmation.dose)
        withAnimation { self.confirmation = nil }
        let what = confirmation.dose.source.map { "\($0), \(numberText(confirmation.dose.mg)) mg" } ?? "\(numberText(confirmation.dose.mg)) mg"
        UIAccessibility.post(notification: .announcement, argument: "Removed \(what).")
    }

    private func draft(for sheet: DoseSheet) -> CustomDoseDraft {
        switch sheet {
        case .new: customDraft ?? CaffeineLog.newDraft(now: model.now)
        case .edit(let dose): CaffeineLog.editDraft(for: dose)
        }
    }

    private func handle(_ result: DoseEntrySheet.Result, for sheet: DoseSheet) {
        switch (result, sheet) {
        case (.saved(let draft), .new):
            _ = model.addCustomDose(draft)
            customDraft = nil
            addedCount += 1
        case (.saved(let draft), .edit(let dose)):
            model.correctDose(id: dose.id, with: draft)
            addedCount += 1
        case (.deleted, .edit(let dose)):
            model.deleteDose(id: dose.id)
        case (.cancelled(let draft), .new):
            // A new entry's draft survives Cancel.
            customDraft = draft
        default:
            break
        }
    }
}

enum DoseSheet: Identifiable, Hashable {
    case new
    case edit(Dose)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let dose): dose.id
        }
    }
}

/// One entry: amount, drink, full local date and time, and its source.
/// Sample entries are read-only and visibly quieter.
struct DoseRow: View {
    @Environment(AppModel.self) private var model
    let dose: Dose
    let onEdit: () -> Void

    var body: some View {
        let editable = CaffeineLog.isEditable(dose)
        let content = HStack(alignment: .top, spacing: Metrics.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(CaffeineLog.title(dose))
                    .font(.headline)
                    .foregroundStyle(editable ? Palette.textPrimary : Palette.textSecondary)
                Text(model.text.fullDateTime(dose.timestamp))
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                if let note = CaffeineLog.displayNote(dose) {
                    Text(note).font(.footnote).foregroundStyle(Palette.textSecondary)
                }
            }
            Spacer(minLength: 0)
            Text(editable ? "Manual" : "Sample Data")
                .font(.caption.weight(.semibold))
                .foregroundStyle(editable ? Palette.textSecondary : StatusTone.warning.foreground)
            if editable {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(Metrics.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())

        Group {
            if editable {
                Button(action: onEdit) { content }
                    .buttonStyle(.plain)
                    .accessibilityHint("Edit or delete this entry")
            } else {
                content
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CaffeineLog.describe(dose, formatDateTime: model.text.fullDateTime))
        .accessibilityAddTraits(editable ? .isButton : [])
    }
}
